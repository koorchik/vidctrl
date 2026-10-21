// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get dropZoneTitle => 'Drop videos or folders here';

  @override
  String get dropZoneHint => 'Your original files are never changed.';

  @override
  String get addVideos => 'Add videos';

  @override
  String get addFolder => 'Add folder';

  @override
  String get yourVideos => 'Your videos';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String get scenarioArchiveTitle => 'For the archive';

  @override
  String get scenarioArchiveHint =>
      'Camera videos take far less space and look the same as the originals. Shooting dates, camera details, sound and colours are kept.';

  @override
  String get scenarioResolveTitle => 'Edit in DaVinci Resolve';

  @override
  String get scenarioResolveHint =>
      'Makes videos open with picture and sound in Resolve on Linux.';

  @override
  String get archiveFormatTitle => 'Format';

  @override
  String get archiveAv1 => 'Smallest file';

  @override
  String get archiveAv1Hint =>
      'Plays on computers and newer devices: iPhone 15 Pro and later, Macs with M3, TVs from about 2020.';

  @override
  String get archiveHevc => 'Works everywhere';

  @override
  String get archiveHevcHint =>
      'The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.';

  @override
  String get archiveSpeedTitle => 'Speed';

  @override
  String get archiveCpu => 'Thorough';

  @override
  String get archiveCpuHint =>
      'The processor encodes: slower, and the file is the smallest.';

  @override
  String get archiveGpu => 'Fast';

  @override
  String get archiveGpuHint =>
      'The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.';

  @override
  String get presetResolveStudio => 'Resolve Studio';

  @override
  String get presetResolveStudioHint =>
      'Usually only the sound needs fixing, which takes seconds.';

  @override
  String get presetResolveFree => 'Free Resolve';

  @override
  String get presetResolveFreeHint =>
      'The picture is converted too. Files become much larger.';

  @override
  String get sizeTitle => 'File size';

  @override
  String get sizeSmallest => 'Smallest';

  @override
  String get sizeSmaller => 'Smaller';

  @override
  String get sizeBalanced => 'Recommended';

  @override
  String get sizeBest => 'Best quality';

  @override
  String get convertVideoTitle => 'Also convert the picture';

  @override
  String get convertVideoHint =>
      'Turn on if videos play choppily, as they can without an NVIDIA graphics card.';

  @override
  String get saveTitle => 'Where to save';

  @override
  String get saveNextToOriginals =>
      'Next to the originals, in a “Converted” folder';

  @override
  String get saveChooseFolder => 'Change…';

  @override
  String get saveReset => 'Use the default';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Continue';

  @override
  String get sampleFromStart => 'From the beginning';

  @override
  String get sampleFromMiddle => 'From the middle';

  @override
  String get remove => 'Remove';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Try again';

  @override
  String get showInFolder => 'Show in folder';

  @override
  String get dragToReorder => 'Drag to change the order';

  @override
  String get statusChecking => 'Checking…';

  @override
  String get statusReadyAsIs => 'Ready as is';

  @override
  String get statusQuickFix => 'Quick, the picture stays untouched';

  @override
  String get statusFullConversion => 'Will be converted';

  @override
  String get statusUnsupported => 'No picture in this file';

  @override
  String get statusUnreadable => 'Not a video file';

  @override
  String get statusFailed => 'Could not convert';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusStarting => 'Starting…';

  @override
  String progressLeft(String time) {
    return '$time left';
  }

  @override
  String aboutSize(String size) {
    return 'about $size';
  }

  @override
  String percentSmaller(int percent) {
    return '$percent% smaller';
  }

  @override
  String percentLarger(int percent) {
    return '$percent% larger';
  }

  @override
  String videoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String convertingCount(int current, int total) {
    return 'Converting $current of $total';
  }

  @override
  String get allDone => 'All done';

  @override
  String savedSummary(String before, String after) {
    return '$before became $after';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String durationHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get unitGB => 'GB';

  @override
  String get unitMB => 'MB';

  @override
  String get unitKB => 'KB';

  @override
  String get playOriginal => 'Play original';

  @override
  String get close => 'Close';

  @override
  String get details => 'Details';

  @override
  String get engineMissingTitle => 'The video engine is missing';

  @override
  String get engineMissingBody =>
      'This app needs FFmpeg to convert videos, and could not find the copy that comes with it. Download VidCtrl again and install it.';

  @override
  String get engineBuiltIn => 'Video engine: built in';

  @override
  String get engineSystem => 'Video engine: the computer\'s';

  @override
  String get aboutTitle => 'About VidCtrl';

  @override
  String get licences => 'Licences';

  @override
  String get website => 'Website';

  @override
  String get camctrlQuestion => 'Shooting on Blackmagic?';

  @override
  String get camctrlLink => 'Control the camera with CamCtrl';

  @override
  String get developmentBuild => 'VidCtrl, development build';

  @override
  String get checkForUpdates => 'Check for updates…';

  @override
  String get updateChecking => 'Looking for a new version…';

  @override
  String get updateAvailableTitle => 'A new version is out';

  @override
  String updateAvailableBody(String latest, String current) {
    return 'VidCtrl $latest is available. You have $current.';
  }

  @override
  String get updateDownload => 'Download';

  @override
  String get updateLater => 'Not now';

  @override
  String get updateNoneTitle => 'VidCtrl is up to date';

  @override
  String updateNoneBody(String current) {
    return '$current is the newest version.';
  }

  @override
  String get updateFailedTitle => 'Could not check for updates';

  @override
  String get updateFailedBody => 'Check the internet connection and try again.';

  @override
  String newVersionTag(String version) {
    return 'New version $version';
  }

  @override
  String get startingUp => 'Getting ready…';

  @override
  String get quitTitle => 'Stop converting and quit?';

  @override
  String get quitBody =>
      'The video being converted will be discarded. Finished videos are kept.';

  @override
  String get quit => 'Quit';

  @override
  String get keepConverting => 'Keep converting';

  @override
  String get more => 'More';

  @override
  String get showCommand => 'Show the command';

  @override
  String get commandTitle => 'The command for this video';

  @override
  String get commandIntro =>
      'This is what the app runs for this video. Copy it to run it yourself in a terminal, or to adjust it.';

  @override
  String get commandOneLine => 'One line';

  @override
  String get commandExplained => 'Explained';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get moreOptions => 'More options…';

  @override
  String get optionCodecTitle => 'Editing format';

  @override
  String get cmdHideBanner => 'Do not print version information';

  @override
  String get cmdSeek => 'Start from this point of the video, in seconds';

  @override
  String get cmdInput => 'The video to convert';

  @override
  String get cmdLength => 'Convert only this many seconds';

  @override
  String get cmdKeepPicture => 'Take the picture from the original';

  @override
  String get cmdKeepSound => 'Take every sound track, if there are any';

  @override
  String get cmdNoPicture => 'Leave the picture out';

  @override
  String get cmdNoSound => 'Leave the sound out';

  @override
  String get cmdKeepMetadata => 'Keep dates, titles and timecode';

  @override
  String get cmdDropMetadata => 'Remove dates, titles and other details';

  @override
  String get cmdPictureCopy => 'Picture: copy as it is, no quality loss';

  @override
  String get cmdPictureEncoder => 'Picture: re-encode with this encoder';

  @override
  String get cmdSoundCopy => 'Sound: copy as it is';

  @override
  String get cmdSoundEncoder => 'Sound: convert to this format';

  @override
  String get cmdSpeedPreset =>
      'Effort: slower makes a smaller file at the same quality';

  @override
  String get cmdQuality =>
      'Quality target (for most encoders a lower number means better quality and a bigger file)';

  @override
  String get cmdProfile => 'Variant of the format';

  @override
  String get cmdEncoderTuning => 'Fine tuning of the encoder';

  @override
  String get cmdPixelFormat => 'Colour precision of the picture';

  @override
  String get cmdFilter => 'Processing applied to the picture';

  @override
  String get cmdSoundBitrate => 'Sound quality, as data per second';

  @override
  String get cmdConstantFrameRate => 'Make the frame timing even';

  @override
  String get cmdFrameRate => 'Frames per second';

  @override
  String get cmdKeyframeInterval =>
      'A complete frame at least this often, for smooth scrubbing';

  @override
  String get cmdPlayerTag =>
      'Label that lets Apple players recognise the video';

  @override
  String get cmdFastStart =>
      'Put the index first, so playback can start while downloading';

  @override
  String get cmdFastStartKeepingTags =>
      'Put the index first, so playback can start while downloading, and keep the camera\'s make and model';

  @override
  String get cmdLevelLimit =>
      'Stay within what every player of video this size handles';

  @override
  String get cmdDropTag =>
      'Leave out the original\'s file type tag, which does not fit the new file';

  @override
  String get cmdContainer => 'File type of the result';

  @override
  String get cmdOutput => 'Where the result is written';

  @override
  String get scenarioShareTitle => 'Send to a phone';

  @override
  String get scenarioShareHint =>
      'Small and plays on any phone, in Telegram and other messengers. In Telegram, send it as a file to keep this quality.';

  @override
  String get scenarioAudioTitle => 'Get the sound';

  @override
  String get scenarioAudioHint =>
      'Saves the sound of a video as a separate file.';

  @override
  String get scenarioPrivacyTitle => 'Remove personal data';

  @override
  String get scenarioPrivacyHint =>
      'Removes the hidden notes about place, date, camera and author before you share a video. What is seen and heard stays the same.';

  @override
  String get scenarioRemuxTitle => 'Change file type';

  @override
  String get scenarioRemuxHint =>
      'Puts the video into another kind of file in seconds, without touching the picture quality.';

  @override
  String get optionSizeTitle => 'Size';

  @override
  String get shareSmall => 'Smaller';

  @override
  String get shareStandard => 'Standard';

  @override
  String get optionFormatTitle => 'File type';

  @override
  String get formatOriginal => 'As it is';

  @override
  String get optionModeTitle => 'How thoroughly';

  @override
  String get modeQuick => 'Quick';

  @override
  String get modeThorough => 'Thorough';

  @override
  String get modeThoroughHint =>
      'Thorough rebuilds the picture and sound from scratch. It takes much longer and is the safest.';

  @override
  String get statusNoSound => 'No sound in this file';

  @override
  String get statusCannotHold => 'This file type cannot hold this video';

  @override
  String get estimating => 'measuring size…';

  @override
  String takesAbout(String time) {
    return 'takes about $time';
  }

  @override
  String get languageSystem => 'Same as the computer';

  @override
  String get lookTitle => 'Look';

  @override
  String get lookCozy => 'Cozy';

  @override
  String get lookPro => 'Professional';

  @override
  String get techPictureCopied => 'picture copied as is';

  @override
  String get techSoundCopied => 'sound copied as is';

  @override
  String get techNoSound => 'no sound';

  @override
  String get techNoReencode => 'no re-encoding';

  @override
  String get techOnlySound => 'only the sound changes';

  @override
  String techUpTo(String lines) {
    return 'up to $lines';
  }

  @override
  String inQueueCount(int count) {
    return '$count in queue';
  }

  @override
  String doneCount(int count) {
    return '$count done';
  }

  @override
  String get videoDetails => 'Video details';

  @override
  String recipeTitleSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'What to do with $count selected videos',
      one: 'What to do with the selected video',
    );
    return '$_temp0';
  }

  @override
  String get recipeTitleNone => 'What to do';

  @override
  String get selectVideosHint =>
      'Select videos on the left to choose what to do with them.';

  @override
  String get convertTitle => 'Convert';

  @override
  String get convertWhole => 'Whole video';

  @override
  String get convertSample => '10-second sample';

  @override
  String get addToQueue => 'Add to queue';

  @override
  String addAllToQueue(int count) {
    return 'Add all ($count)';
  }

  @override
  String get alreadyQueued => 'Already in the queue';

  @override
  String samplesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count samples of 10 seconds',
      one: '1 sample of 10 seconds',
    );
    return '$_temp0';
  }

  @override
  String get queueTitle => 'Queue';

  @override
  String get queueEmpty =>
      'Choose videos and what to do, then press Add to queue. Converting starts by itself.';

  @override
  String get queuePaused => 'Paused';

  @override
  String get jobWaiting => 'Waiting';

  @override
  String pausedAt(int percent) {
    return 'Paused at $percent%';
  }

  @override
  String get jobSkipped => 'Nothing to do: already right';

  @override
  String get sampleChip => 'Sample 10 s';

  @override
  String sampleResult(String size, String fullSize, String time) {
    return 'Sample $size · whole video about $fullSize, about $time';
  }

  @override
  String tookTime(String time) {
    return 'took $time';
  }

  @override
  String get play => 'Play';

  @override
  String get convertWholeVideo => 'Convert whole video';

  @override
  String get originalDetails => 'Details of the original';

  @override
  String get resultDetails => 'Details of the result';

  @override
  String get compareWithOriginal => 'Compare with the original';

  @override
  String comparingWithOriginal(int percent) {
    return 'Comparing with the original… $percent%';
  }

  @override
  String get stopComparing => 'Stop comparing';

  @override
  String get closenessSame => 'Looks the same as the original';

  @override
  String get closenessVeryClose => 'Very close to the original';

  @override
  String get closenessDiffers => 'Differences may be visible';

  @override
  String get compareFailed => 'Could not compare';

  @override
  String vmafScore(String score) {
    return 'VMAF $score';
  }

  @override
  String xpsnrScore(String score) {
    return 'XPSNR $score dB';
  }

  @override
  String get useSettings => 'Use these settings';

  @override
  String get removeFromList => 'Remove from list';

  @override
  String get detailsViewEncoding => 'Encoding';

  @override
  String get detailsViewMetadata => 'All metadata';

  @override
  String get detailsViewReport => 'Full report';

  @override
  String get noTags => 'No tags';

  @override
  String get groupFile => 'File';

  @override
  String groupVideo(int number) {
    return 'Video track $number';
  }

  @override
  String groupAudio(int number) {
    return 'Audio track $number';
  }

  @override
  String groupSubtitle(int number) {
    return 'Subtitles $number';
  }

  @override
  String get groupTimecode => 'Timecode';

  @override
  String groupData(int number) {
    return 'Data track $number';
  }

  @override
  String groupAttachment(int number) {
    return 'Attachment $number';
  }

  @override
  String get groupChapters => 'Chapters';

  @override
  String groupChapter(int number) {
    return 'Chapter $number';
  }

  @override
  String get fieldContainer => 'Container';

  @override
  String get fieldSize => 'Size';

  @override
  String get fieldDuration => 'Duration';

  @override
  String get fieldBitrate => 'Bitrate';

  @override
  String get fieldTracks => 'Tracks';

  @override
  String get fieldCodec => 'Codec';

  @override
  String get fieldResolution => 'Resolution';

  @override
  String get fieldAspectRatio => 'Aspect ratio';

  @override
  String get fieldFrameRate => 'Frame rate';

  @override
  String get fieldBitDepth => 'Bit depth';

  @override
  String get fieldChroma => 'Chroma subsampling';

  @override
  String get fieldPixelFormat => 'Pixel format';

  @override
  String get fieldColorPrimaries => 'Colour primaries';

  @override
  String get fieldColorTransfer => 'Transfer';

  @override
  String get fieldColorMatrix => 'Matrix';

  @override
  String get fieldColorRange => 'Range';

  @override
  String get fieldHdr => 'HDR';

  @override
  String get fieldMasteringDisplay => 'Mastering display';

  @override
  String get fieldLightLevel => 'Light level';

  @override
  String get fieldScanType => 'Scan type';

  @override
  String get fieldRotation => 'Rotation';

  @override
  String get fieldFrames => 'Frames';

  @override
  String get fieldChannels => 'Channels';

  @override
  String get fieldSampleRate => 'Sample rate';

  @override
  String get fieldSampleFormat => 'Sample format';

  @override
  String get fieldLanguage => 'Language';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldDefaultTrack => 'Default track';

  @override
  String get fieldTimecode => 'Timecode';

  @override
  String get fieldFileName => 'File name';

  @override
  String get fieldChapter => 'Chapter';

  @override
  String get noteVariable => 'variable';

  @override
  String get noteProgressive => 'progressive';

  @override
  String get noteInterlaced => 'interlaced';

  @override
  String get noteNotStated => 'not stated';

  @override
  String get noteYes => 'yes';

  @override
  String get noteNo => 'no';

  @override
  String get appTitle => 'VidCtrl';

  @override
  String get noteVariableFrameRate => 'Uneven frame timing will be fixed.';

  @override
  String get noteHevc422 =>
      'Without a recent NVIDIA card, this recording format may play choppily in Resolve.';

  @override
  String get noteExperimentalAv1 =>
      'Smallest files are harder to edit smoothly.';

  @override
  String get noteHdrToneMapped =>
      'Very bright colours will be adjusted to look right on any screen.';

  @override
  String get noteHdrNotConverted =>
      'This video uses extra-bright colours that may look washed out on a phone.';

  @override
  String get noteAudioConvertedToFit =>
      'The sound will be converted to fit this file type.';

  @override
  String get selectAll => 'Select all';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get convertSampleShort => 'Sample';

  @override
  String get sampleFirst => 'first 10 s';

  @override
  String get sampleMiddle => 'middle 10 s';

  @override
  String get personalTag =>
      'Personal detail: who, where, when or with what the video was made';
}
