import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/ffmpeg/capabilities.dart';
import 'package:vidctrl/core/ffmpeg/command_builder.dart';
import 'package:vidctrl/core/media/media_info.dart';
import 'package:vidctrl/core/quality/quality_meter.dart';
import 'package:vidctrl/core/scenarios/archive.dart';
import 'package:vidctrl/core/scenarios/remux.dart';
import 'package:vidctrl/core/scenarios/resolve_linux.dart';
import 'package:vidctrl/core/scenarios/save_space.dart';
import 'package:vidctrl/core/scenarios/scenario.dart';
import 'package:vidctrl/core/scenarios/strip_metadata.dart';

import '../../support/fake_media.dart';

void main() {
  group('The comparison command', () {
    test('compares the whole result with the whole original', () {
      final args = comparisonArgs(
        original: '/videos/clip.mov',
        result: '/videos/Converted/clip_av1-crf35.mp4',
      );

      expect(
        args,
        containsAllInOrder([
          '-i',
          'file:/videos/Converted/clip_av1-crf35.mp4',
          '-i',
          'file:/videos/clip.mov',
        ]),
      );
      expect(args, isNot(contains('-ss')));
      expect(args, isNot(contains('-t')));
      expect(args, containsAllInOrder(['-f', 'null', '-']));
    });

    test('pairs frames by order and stops with the shorter file', () {
      final filter = _filter(
        comparisonArgs(original: '/videos/a.mov', result: '/videos/b.mp4'),
      );

      expect(filter, contains('setpts=N'));
      // The original first: `xpsnr` weighs by how busy the first picture is.
      expect(filter, contains('[r][d]xpsnr=shortest=1'));
      // `xpsnr` misreads 10-bit rows that are not packed in memory.
      expect(filter, contains('crop=trunc(iw/32)*32:ih:0:0'));
      expect(filter, contains('yuv420p10le,copy'));
    });

    test('compares a sample with the same piece of the original', () {
      final args = comparisonArgs(
        original: '/videos/clip.mov',
        result: '/videos/Samples/clip_sample10s.mp4',
        range: const SampleRange(
          start: Duration(seconds: 25),
          length: Duration(seconds: 10),
        ),
      );

      // Both before the original: they apply to it, not to the result.
      expect(
        args,
        containsAllInOrder([
          '-i',
          'file:/videos/Samples/clip_sample10s.mp4',
          '-ss',
          '25.000',
          '-t',
          '10.000',
          '-i',
          'file:/videos/clip.mov',
        ]),
      );
    });

    test('without a VMAF model only XPSNR is measured', () {
      final args = comparisonArgs(
        original: '/videos/a.mov',
        result: '/videos/b.mp4',
      );

      expect(_filter(args), isNot(contains('libvmaf')));
      expect(args, isNot(contains('-map')));
    });

    test('with a VMAF model both are measured in one pass', () {
      final args = comparisonArgs(
        original: '/videos/a.mov',
        result: '/videos/b.mp4',
        vmafModel: 'vmaf_4k_v0.6.1',
        threads: 8,
      );

      expect(_filter(args), contains('[r][d]xpsnr=shortest=1'));
      // VMAF wants the copy first.
      expect(
        _filter(args),
        contains('[dv][rv]libvmaf=model=version=vmaf_4k_v0.6.1:n_threads=8'),
      );
      // Each file is decoded once and shared by the two measures.
      expect('split'.allMatches(_filter(args)), hasLength(2));
      expect(args, containsAllInOrder(['-map', '[x]', '-map', '[v]']));
    });

    test('pictures larger than 1080p are measured with the 4K model', () {
      expect(vmafModelFor(3840, 2160), 'vmaf_4k_v0.6.1');
      expect(vmafModelFor(2560, 1440), 'vmaf_4k_v0.6.1');
      expect(vmafModelFor(1920, 1080), 'vmaf_v0.6.1');
      expect(vmafModelFor(1080, 1920), 'vmaf_v0.6.1');
    });

    test('a sample from the start needs no seek', () {
      final args = comparisonArgs(
        original: '/videos/clip.mov',
        result: '/videos/Samples/clip_sample10s.mp4',
        range: const SampleRange(length: Duration(seconds: 10)),
      );

      expect(args, isNot(contains('-ss')));
      expect(args, containsAllInOrder(['-t', '10.000']));
    });
  });

  group('Scores frame by frame', () {
    test('a log is asked for with VMAF as CSV', () {
      final args = comparisonArgs(
        original: '/videos/a.mov',
        result: '/videos/a.mp4',
        vmafModel: 'vmaf_v0.6.1',
        frameLog: '/tmp/log.csv',
      );

      expect(
        args[args.indexOf('-lavfi') + 1],
        contains(
          'libvmaf=model=version=vmaf_v0.6.1:n_threads=1:shortest=1'
          ':log_fmt=csv:log_path=/tmp/log.csv[v]',
        ),
      );
    });

    test('without VMAF, the XPSNR statistics are the log', () {
      final args = comparisonArgs(
        original: '/videos/a.mov',
        result: '/videos/a.mp4',
        frameLog: '/tmp/log.txt',
      );

      expect(
        args[args.indexOf('-lavfi') + 1],
        endsWith('xpsnr=shortest=1:stats_file=/tmp/log.txt'),
      );
    });

    test('a path is escaped for the filter graph', () {
      expect(
        escapeFilterPath("/tmp/it's [a],b;c:d/log.csv"),
        r"/tmp/it\\\'s \[a\]\,b\;c\\:d/log.csv",
      );
    });

    test('a Windows path keeps its drive', () {
      expect(
        escapeFilterPath(r'C:\Users\Ann\AppData\Local\Temp\log.csv'),
        r'C\\:/Users/Ann/AppData/Local/Temp/log.csv',
      );
    });

    test('VMAF is read from its column of the CSV', () {
      const csv =
          'Frame,integer_adm2,integer_motion,vmaf,\n'
          '0,0.96,0.00,87.97,\n'
          '1,0.95,0.77,87.44,\n';

      expect(frameScores(csv), [87.97, 87.44]);
    });

    test('XPSNR is read from its statistics', () {
      const log =
          'n:    1  XPSNR y: 46.0236  XPSNR u: 53.7467  XPSNR v: 53.1902\n'
          'n:    2  XPSNR y: inf  XPSNR u: inf  XPSNR v: inf\n';

      expect(frameScores(log), [46.0236, double.infinity]);
    });

    test('an empty log has no scores', () {
      expect(frameScores(''), isEmpty);
    });
  });

  group('Reading the score', () {
    test('the last luma score is taken', () {
      expect(
        parseXpsnr([
          'Input #0, mov,mp4,m4a,3gp,3g2,mj2, from file:a.mp4:',
          '[Parsed_xpsnr_6 @ 0x7d27] XPSNR  y: 38.7211  u: 40.9880  '
              'v: 42.0557  (minimum: 38.7211)',
        ]),
        38.7211,
      );
    });

    test('identical pictures score infinity', () {
      expect(
        parseXpsnr(['[Parsed_xpsnr_6 @ 0x1] XPSNR  y: inf  u: inf  v: inf']),
        double.infinity,
      );
    });

    test('no score when FFmpeg printed none', () {
      expect(parseXpsnr(['Invalid data found when processing input']), isNull);
      expect(parseVmaf(['Invalid data found when processing input']), isNull);
    });

    test('the VMAF score is read', () {
      expect(
        parseVmaf(['[Parsed_libvmaf_7 @ 0x7e3c] VMAF score: 96.043211']),
        96.043211,
      );
    });
  });

  group('How close', () {
    for (final (vmaf, closeness) in [
      (99.2, Closeness.same),
      (96.0, Closeness.same),
      (95.0, Closeness.same),
      (94.9, Closeness.veryClose),
      (93.0, Closeness.veryClose),
      (92.5, Closeness.differs),
    ]) {
      test('VMAF $vmaf is ${closeness.name}', () {
        expect(closenessOfVmaf(vmaf), closeness);
      });
    }

    test('VMAF decides where it was measured', () {
      // The archive goal's AV1 of a grainy 4K clip: below the XPSNR target,
      // and nothing to see.
      expect(closenessOf(xpsnr: 40.6, vmaf: 96.0), Closeness.same);
      // The blocky file of a faulty encoder.
      expect(closenessOf(xpsnr: 38.7, vmaf: 92.5), Closeness.differs);
    });

    test('XPSNR decides without VMAF', () {
      expect(closenessOf(xpsnr: 40.6), Closeness.veryClose);
    });

    test('a video is as close as its poorest piece', () {
      // A dark film: most pieces fine, one dark scene not.
      final worst = QualityScore.worstOf(const [
        QualityScore(41.0, vmaf: 96.5),
        QualityScore(38.0, vmaf: 89.5),
        QualityScore(39.2, vmaf: 97.2),
      ])!;

      expect(worst.lumaDb, 38.0);
      expect(worst.vmaf, 89.5);
      expect(worst.closeness, Closeness.differs);
    });

    test('a piece without VMAF leaves the video without VMAF', () {
      final worst = QualityScore.worstOf(const [
        QualityScore(43.0, vmaf: 97.0),
        QualityScore(42.5),
      ])!;

      expect(worst.vmaf, isNull);
      expect(worst.closeness, Closeness.same);
    });

    test('no pieces, no score', () {
      expect(QualityScore.worstOf(const []), isNull);
    });

    for (final (db, closeness) in [
      (double.infinity, Closeness.same),
      (45.1, Closeness.same),
      (42.0, Closeness.same),
      (41.9, Closeness.veryClose),
      (40.6, Closeness.veryClose),
      (40.0, Closeness.veryClose),
      (39.9, Closeness.differs),
      (38.7, Closeness.differs),
    ]) {
      test('XPSNR $db dB is ${closeness.name}', () {
        expect(closenessOfXpsnr(db), closeness);
      });
    }
  });

  group('Which results can be compared', () {
    const hlg = ColorInfo(
      primaries: 'bt2020',
      transfer: 'arib-std-b67',
      space: 'bt2020nc',
      range: 'tv',
    );
    // A phone's variable frame rate: declared 30, averaging 29.
    final phoneVideo = clip(fps: 29, nominalFps: 30);

    for (final (name, plan, comparable) in [
      (
        'an archive copy',
        const ArchivePreset().plan(clip(), const {}, softwareOnly),
        true,
      ),
      (
        'an archive copy of a 4:2:2 video, whose colour is only subsampled',
        const ArchivePreset().plan(
          clip(pixFmt: 'yuv422p10le'),
          const {},
          softwareOnly,
        ),
        true,
      ),
      (
        'an archive copy made at a constant frame rate',
        const ArchivePreset().plan(phoneVideo, const {}, softwareOnly),
        false,
      ),
      (
        'a Resolve copy',
        ResolveLinuxPreset.free.plan(clip(), const {}, softwareOnly),
        true,
      ),
      (
        'a smaller copy at a smaller size',
        const SaveSpacePreset().plan(clip(), const {}, softwareOnly),
        false,
      ),
      (
        'a smaller copy already small enough',
        const SaveSpacePreset().plan(
          clip(width: 1920, height: 1080),
          const {},
          softwareOnly,
        ),
        true,
      ),
      (
        'a smaller copy at half the frame rate',
        const SaveSpacePreset().plan(
          clip(width: 1920, height: 1080, fps: 60),
          const {},
          softwareOnly,
        ),
        false,
      ),
      (
        'a smaller copy of an HDR video, tone-mapped',
        const SaveSpacePreset().plan(
          clip(width: 1920, height: 1080, pixFmt: 'yuv420p10le', color: hlg),
          const {},
          withToneMapping,
        ),
        false,
      ),
      (
        'a thoroughly cleaned copy',
        const StripMetadataPreset().plan(clip(), const {
          StripMetadataPreset.mode: 'thorough',
        }, softwareOnly),
        true,
      ),
      (
        'a quickly cleaned copy, its picture copied',
        const StripMetadataPreset().plan(clip(), const {}, softwareOnly),
        false,
      ),
      (
        'a change of file type, its picture copied',
        const RemuxPreset().plan(
          clip(container: mkvContainer),
          const {},
          softwareOnly,
        ),
        false,
      ),
    ]) {
      test('${comparable ? '' : 'not '}$name', () {
        expect(plan.kind, isNot(PlanKind.unsupported));
        expect(canComparePlan(plan), comparable);
      });
    }

    test('and only with an FFmpeg that has the filter that compares', () {
      final plan = const ArchivePreset().plan(clip(), const {}, softwareOnly);
      const noXpsnr = Capabilities(
        ffmpegVersion: 'test',
        encoders: {'libsvtav1'},
      );

      expect(comparableHere(plan, softwareOnly), isTrue);
      expect(comparableHere(plan, noXpsnr), isFalse);
    });
  });
}

String _filter(List<String> args) => args[args.indexOf('-lavfi') + 1];
