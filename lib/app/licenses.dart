import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds what comes with the app beside its Dart packages to the licences
/// page: FFmpeg, which runs as separate programs, and the bundled fonts.
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    final ffmpeg = await rootBundle.loadString('assets/licenses/ffmpeg.txt');
    final gpl = await rootBundle.loadString('assets/licenses/gpl-3.0.txt');
    yield LicenseEntryWithLineBreaks(['FFmpeg'], '$ffmpeg\n\n$gpl');
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto-LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'JetBrains Mono',
    ], await rootBundle.loadString('assets/fonts/JetBrainsMono-OFL.txt'));
  });
}
