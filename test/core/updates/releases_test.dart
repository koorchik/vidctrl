import 'package:flutter_test/flutter_test.dart';
import 'package:vidctrl/core/updates/releases.dart';

Version v(String text) => Version.tryParse(text)!;

void main() {
  group('versions are ordered as people expect', () {
    // Each is older than the next.
    const ascending = [
      '0.9.9',
      '0.10.0',
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
      '1.0.1',
      '1.1.0',
      '2.0.0',
    ];
    for (var i = 0; i + 1 < ascending.length; i++) {
      test('${ascending[i]} < ${ascending[i + 1]}', () {
        expect(v(ascending[i + 1]) > v(ascending[i]), isTrue);
        expect(v(ascending[i]) > v(ascending[i + 1]), isFalse);
      });
    }
  });

  test('a tag reads as its version', () {
    expect(v('v0.3.0'), v('0.3.0'));
    expect('${v('v0.3.0')}', '0.3.0');
    expect('${v('v1.0.0-dev.1')}', '1.0.0-dev.1');
  });

  test('build details do not make a version newer', () {
    expect(v('1.0.0+42') > v('1.0.0'), isFalse);
    expect(v('1.0.0') > v('1.0.0+42'), isFalse);
  });

  test('what is not a version is not read as one', () {
    for (final text in ['', 'dev', '1.0', '1.0.0.0', 'v', '1.x.0', 'latest']) {
      expect(Version.tryParse(text), isNull, reason: text);
    }
  });

  group('GitHub\'s description of a release', () {
    test('gives its version and page', () {
      final release = parseGitHubRelease({
        'tag_name': 'v0.4.0',
        'html_url': 'https://github.com/owner/vidctrl/releases/tag/v0.4.0',
        'draft': false,
      });
      expect(release.version, v('0.4.0'));
      expect(
        '${release.page}',
        'https://github.com/owner/vidctrl/releases/tag/v0.4.0',
      );
    });

    test('is refused without a version tag or a page', () {
      for (final json in <Object?>[
        null,
        'Not Found',
        {'message': 'Not Found'},
        {'tag_name': 'nightly', 'html_url': 'https://example.com/r'},
        {'tag_name': 'v1.0.0'},
        {'tag_name': 'v1.0.0', 'html_url': 'javascript:alert(1)'},
      ]) {
        expect(
          () => parseGitHubRelease(json),
          throwsA(isA<ReleaseCheckFailed>()),
          reason: '$json',
        );
      }
    });
  });
}
