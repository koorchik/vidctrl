/// Turns FFmpeg arguments into text a person can read, copy and run.
///
/// The app itself never runs these strings: it passes the argument list
/// straight to the process. This is for showing what it does.
library;

import 'dart:io';

/// The terminal the command is written for.
enum ShellStyle {
  /// bash and zsh, on Linux and macOS.
  posix,

  /// PowerShell, the default terminal on Windows.
  powershell;

  static ShellStyle get current =>
      Platform.isWindows ? ShellStyle.powershell : ShellStyle.posix;
}

/// What one part of the command does. The UI turns these into sentences.
enum ArgMeaning {
  hideBanner,
  seek,
  input,
  length,
  keepPicture,
  keepSound,
  noPicture,
  noSound,
  keepMetadata,
  dropMetadata,
  pictureCopy,
  pictureEncoder,
  soundCopy,
  soundEncoder,
  speedPreset,
  quality,
  profile,
  encoderTuning,
  pixelFormat,
  filter,
  soundBitrate,
  constantFrameRate,
  frameRate,
  keyframeInterval,
  playerTag,
  fastStart,
  fastStartKeepingTags,
  dropTag,
  levelLimit,
  container,
  output,
  other,
}

/// An option together with its value, e.g. `-crf 25`.
class CommandPart {
  const CommandPart(this.args, this.meaning);

  final List<String> args;
  final ArgMeaning meaning;
}

const _flags = {'-hide_banner', '-y', '-nostats', '-vn', '-an'};

/// Splits an argument list into options with their values.
List<CommandPart> splitCommand(List<String> args) {
  final parts = <CommandPart>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    final isLast = i == args.length - 1;
    if (!arg.startsWith('-') || isLast && !_flags.contains(arg)) {
      parts.add(
        CommandPart([arg], isLast ? ArgMeaning.output : ArgMeaning.other),
      );
    } else if (_flags.contains(arg)) {
      parts.add(CommandPart([arg], _meaning(arg, '')));
    } else {
      final value = args[++i];
      parts.add(CommandPart([arg, value], _meaning(arg, value)));
    }
  }
  return parts;
}

ArgMeaning _meaning(String option, String value) => switch (option) {
  '-hide_banner' => ArgMeaning.hideBanner,
  '-ss' => ArgMeaning.seek,
  '-i' => ArgMeaning.input,
  '-t' => ArgMeaning.length,
  '-map' when value.startsWith('0:v') => ArgMeaning.keepPicture,
  '-map' when value.startsWith('0:a') => ArgMeaning.keepSound,
  '-vn' => ArgMeaning.noPicture,
  '-an' => ArgMeaning.noSound,
  '-map_metadata' when value == '-1' => ArgMeaning.dropMetadata,
  '-map_metadata' => ArgMeaning.keepMetadata,
  '-c:v' when value == 'copy' => ArgMeaning.pictureCopy,
  '-c:v' => ArgMeaning.pictureEncoder,
  '-c:a' when value == 'copy' => ArgMeaning.soundCopy,
  '-c:a' => ArgMeaning.soundEncoder,
  '-preset' => ArgMeaning.speedPreset,
  '-crf' ||
  '-cq' ||
  '-global_quality' ||
  '-q:v' ||
  '-qvbr_quality_level' => ArgMeaning.quality,
  '-profile:v' => ArgMeaning.profile,
  '-pix_fmt' => ArgMeaning.pixelFormat,
  '-vf' => ArgMeaning.filter,
  '-b:a' => ArgMeaning.soundBitrate,
  '-fps_mode' => ArgMeaning.constantFrameRate,
  '-r' => ArgMeaning.frameRate,
  '-g' => ArgMeaning.keyframeInterval,
  '-tag:v' => ArgMeaning.playerTag,
  '-movflags' when value.contains('use_metadata_tags') =>
    ArgMeaning.fastStartKeepingTags,
  '-movflags' => ArgMeaning.fastStart,
  '-metadata' when value.endsWith('=') => ArgMeaning.dropTag,
  '-maxrate' || '-bufsize' || '-level' || '-tier' => ArgMeaning.levelLimit,
  '-f' => ArgMeaning.container,
  '-svtav1-params' ||
  '-x265-params' ||
  '-tune' ||
  '-rc' ||
  '-b:v' ||
  '-rc-lookahead' ||
  '-spatial-aq' ||
  '-temporal-aq' ||
  '-b_ref_mode' ||
  '-vendor' ||
  '-usage' ||
  '-quality' ||
  '-extbrc' ||
  '-look_ahead_depth' => ArgMeaning.encoderTuning,
  _ => ArgMeaning.other,
};

final _plainPosix = RegExp(r'^[\w@%+=:,./-]+$');
final _plainPowerShell = RegExp(r'^[\w/\\]+$');

/// Quotes one argument so the shell passes it on unchanged.
String quoteArg(String arg, ShellStyle shell) {
  switch (shell) {
    case ShellStyle.posix:
      if (_plainPosix.hasMatch(arg)) return arg;
      return "'${arg.replaceAll("'", r"'\''")}'";
    case ShellStyle.powershell:
      // PowerShell re-interprets `-name:value`, wildcards and much else, so
      // anything beyond plain words is quoted literally.
      if (_plainPowerShell.hasMatch(arg)) return arg;
      return "'${arg.replaceAll("'", "''")}'";
  }
}

/// The whole command on one line.
String singleLineCommand(
  String executable,
  List<String> args, {
  ShellStyle? shell,
}) {
  final style = shell ?? ShellStyle.current;
  final line = [executable, ...args].map((a) => quoteArg(a, style)).join(' ');
  // A quoted first word is a string to PowerShell, not a command, unless it
  // is called with `&`.
  return style == ShellStyle.powershell && line.startsWith("'")
      ? '& $line'
      : line;
}

/// The command with one option per line and a comment on each, in a form
/// that still runs when pasted into a terminal.
///
/// A backslash-continued command cannot carry comments, so the options are
/// written as an array, which allows them in both shells:
///
/// ```sh
/// args=(
///   -crf 25   # Quality target
/// )
/// ffmpeg "${args[@]}"
/// ```
String explainedCommand(
  String executable,
  List<String> args, {
  required String Function(CommandPart part) describe,
  ShellStyle? shell,
}) {
  final style = shell ?? ShellStyle.current;
  final separator = style == ShellStyle.powershell ? ', ' : ' ';
  final lines = [
    for (final part in splitCommand(args))
      (
        // In a PowerShell array every element is quoted: a bare `-crf` there
        // would be parsed as an operator.
        code: part.args
            .map(
              (a) => style == ShellStyle.powershell
                  ? "'${a.replaceAll("'", "''")}'"
                  : quoteArg(a, style),
            )
            .join(separator),
        comment: describe(part),
      ),
  ];
  // Comments line up in one column. A line too long for that column (a long
  // path, encoder parameters) gets its comment on the line above instead.
  const widest = 36;
  final column = lines
      .map((l) => l.code.length)
      .where((length) => length <= widest)
      .fold(0, (a, b) => a > b ? a : b);

  final buffer = StringBuffer()
    ..writeln(style == ShellStyle.powershell ? r'$ffmpegArgs = @(' : 'args=(');
  for (final line in lines) {
    final comment = line.comment.isEmpty ? '' : '# ${line.comment}';
    if (comment.isNotEmpty && line.code.length > widest) {
      buffer
        ..writeln('  $comment')
        ..writeln('  ${line.code}');
    } else if (comment.isNotEmpty) {
      buffer.writeln('  ${line.code.padRight(column)}  $comment');
    } else {
      buffer.writeln('  ${line.code}');
    }
  }
  buffer
    ..writeln(')')
    ..write(
      style == ShellStyle.powershell
          ? '& ${quoteArg(executable, style)} @ffmpegArgs'
          : '${quoteArg(executable, style)} "\${args[@]}"',
    );
  return buffer.toString();
}
