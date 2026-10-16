import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @dropZoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop videos or folders here'**
  String get dropZoneTitle;

  /// No description provided for @dropZoneHint.
  ///
  /// In en, this message translates to:
  /// **'Your original files are never changed.'**
  String get dropZoneHint;

  /// No description provided for @addVideos.
  ///
  /// In en, this message translates to:
  /// **'Add videos'**
  String get addVideos;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolder;

  /// No description provided for @yourVideos.
  ///
  /// In en, this message translates to:
  /// **'Your videos'**
  String get yourVideos;

  /// No description provided for @clearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get clearFinished;

  /// No description provided for @scenarioArchiveTitle.
  ///
  /// In en, this message translates to:
  /// **'For the archive'**
  String get scenarioArchiveTitle;

  /// No description provided for @scenarioArchiveHint.
  ///
  /// In en, this message translates to:
  /// **'Camera videos take far less space and look the same as the originals. Shooting dates, camera details, sound and colours are kept.'**
  String get scenarioArchiveHint;

  /// No description provided for @scenarioResolveTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit in DaVinci Resolve'**
  String get scenarioResolveTitle;

  /// No description provided for @scenarioResolveHint.
  ///
  /// In en, this message translates to:
  /// **'Makes videos open with picture and sound in Resolve on Linux.'**
  String get scenarioResolveHint;

  /// No description provided for @archiveFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get archiveFormatTitle;

  /// No description provided for @archiveAv1.
  ///
  /// In en, this message translates to:
  /// **'Smallest file'**
  String get archiveAv1;

  /// No description provided for @archiveAv1Hint.
  ///
  /// In en, this message translates to:
  /// **'Plays on computers and newer devices: iPhone 15 Pro and later, Macs with M3, TVs from about 2020.'**
  String get archiveAv1Hint;

  /// No description provided for @archiveHevc.
  ///
  /// In en, this message translates to:
  /// **'Works everywhere'**
  String get archiveHevc;

  /// No description provided for @archiveHevcHint.
  ///
  /// In en, this message translates to:
  /// **'The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.'**
  String get archiveHevcHint;

  /// No description provided for @archiveSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get archiveSpeedTitle;

  /// No description provided for @archiveCpu.
  ///
  /// In en, this message translates to:
  /// **'Thorough'**
  String get archiveCpu;

  /// No description provided for @archiveCpuHint.
  ///
  /// In en, this message translates to:
  /// **'The processor encodes: slower, and the file is the smallest.'**
  String get archiveCpuHint;

  /// No description provided for @archiveGpu.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get archiveGpu;

  /// No description provided for @archiveGpuHint.
  ///
  /// In en, this message translates to:
  /// **'The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.'**
  String get archiveGpuHint;

  /// No description provided for @presetResolveStudio.
  ///
  /// In en, this message translates to:
  /// **'Resolve Studio'**
  String get presetResolveStudio;

  /// No description provided for @presetResolveStudioHint.
  ///
  /// In en, this message translates to:
  /// **'Usually only the sound needs fixing, which takes seconds.'**
  String get presetResolveStudioHint;

  /// No description provided for @presetResolveFree.
  ///
  /// In en, this message translates to:
  /// **'Free Resolve'**
  String get presetResolveFree;

  /// No description provided for @presetResolveFreeHint.
  ///
  /// In en, this message translates to:
  /// **'The picture is converted too. Files become much larger.'**
  String get presetResolveFreeHint;

  /// No description provided for @sizeTitle.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get sizeTitle;

  /// No description provided for @sizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Smallest'**
  String get sizeSmallest;

  /// No description provided for @sizeSmaller.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get sizeSmaller;

  /// No description provided for @sizeBalanced.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get sizeBalanced;

  /// No description provided for @sizeBest.
  ///
  /// In en, this message translates to:
  /// **'Best quality'**
  String get sizeBest;

  /// No description provided for @convertVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Also convert the picture'**
  String get convertVideoTitle;

  /// No description provided for @convertVideoHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on if videos play choppily or show no picture. Needed without an NVIDIA graphics card.'**
  String get convertVideoHint;

  /// No description provided for @saveTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to save'**
  String get saveTitle;

  /// No description provided for @saveNextToOriginals.
  ///
  /// In en, this message translates to:
  /// **'Next to the originals, in a “Converted” folder'**
  String get saveNextToOriginals;

  /// No description provided for @saveChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get saveChooseFolder;

  /// No description provided for @saveReset.
  ///
  /// In en, this message translates to:
  /// **'Use the default'**
  String get saveReset;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get resume;

  /// No description provided for @sampleFromStart.
  ///
  /// In en, this message translates to:
  /// **'From the beginning'**
  String get sampleFromStart;

  /// No description provided for @sampleFromMiddle.
  ///
  /// In en, this message translates to:
  /// **'From the middle'**
  String get sampleFromMiddle;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @showInFolder.
  ///
  /// In en, this message translates to:
  /// **'Show in folder'**
  String get showInFolder;

  /// No description provided for @dragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to change the order'**
  String get dragToReorder;

  /// No description provided for @statusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get statusChecking;

  /// No description provided for @statusReadyAsIs.
  ///
  /// In en, this message translates to:
  /// **'Ready as is'**
  String get statusReadyAsIs;

  /// No description provided for @statusQuickFix.
  ///
  /// In en, this message translates to:
  /// **'Quick, the picture stays untouched'**
  String get statusQuickFix;

  /// No description provided for @statusFullConversion.
  ///
  /// In en, this message translates to:
  /// **'Will be converted'**
  String get statusFullConversion;

  /// No description provided for @statusUnsupported.
  ///
  /// In en, this message translates to:
  /// **'No picture in this file'**
  String get statusUnsupported;

  /// No description provided for @statusUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Not a video file'**
  String get statusUnreadable;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not convert'**
  String get statusFailed;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get statusStarting;

  /// No description provided for @progressLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String progressLeft(String time);

  /// No description provided for @aboutSize.
  ///
  /// In en, this message translates to:
  /// **'about {size}'**
  String aboutSize(String size);

  /// No description provided for @percentSmaller.
  ///
  /// In en, this message translates to:
  /// **'{percent}% smaller'**
  String percentSmaller(int percent);

  /// No description provided for @percentLarger.
  ///
  /// In en, this message translates to:
  /// **'{percent}% larger'**
  String percentLarger(int percent);

  /// No description provided for @videoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 video} other{{count} videos}}'**
  String videoCount(int count);

  /// No description provided for @convertingCount.
  ///
  /// In en, this message translates to:
  /// **'Converting {current} of {total}'**
  String convertingCount(int current, int total);

  /// No description provided for @allDone.
  ///
  /// In en, this message translates to:
  /// **'All done'**
  String get allDone;

  /// No description provided for @savedSummary.
  ///
  /// In en, this message translates to:
  /// **'{before} became {after}'**
  String savedSummary(String before, String after);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String durationSeconds(int seconds);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String durationMinutes(int minutes);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String durationHours(int hours, int minutes);

  /// No description provided for @unitGB.
  ///
  /// In en, this message translates to:
  /// **'GB'**
  String get unitGB;

  /// No description provided for @unitMB.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get unitMB;

  /// No description provided for @unitKB.
  ///
  /// In en, this message translates to:
  /// **'KB'**
  String get unitKB;

  /// No description provided for @playOriginal.
  ///
  /// In en, this message translates to:
  /// **'Play original'**
  String get playOriginal;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @engineMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'The video engine is missing'**
  String get engineMissingTitle;

  /// No description provided for @engineMissingBody.
  ///
  /// In en, this message translates to:
  /// **'This app needs FFmpeg to convert videos, and could not find it. Install FFmpeg and start the app again.'**
  String get engineMissingBody;

  /// No description provided for @startingUp.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get startingUp;

  /// No description provided for @quitTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop converting and quit?'**
  String get quitTitle;

  /// No description provided for @quitBody.
  ///
  /// In en, this message translates to:
  /// **'The video being converted will be discarded. Finished videos are kept.'**
  String get quitBody;

  /// No description provided for @quit.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get quit;

  /// No description provided for @keepConverting.
  ///
  /// In en, this message translates to:
  /// **'Keep converting'**
  String get keepConverting;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @showCommand.
  ///
  /// In en, this message translates to:
  /// **'Show the command'**
  String get showCommand;

  /// No description provided for @commandTitle.
  ///
  /// In en, this message translates to:
  /// **'The command for this video'**
  String get commandTitle;

  /// No description provided for @commandIntro.
  ///
  /// In en, this message translates to:
  /// **'This is what the app runs for this video. Copy it to run it yourself in a terminal, or to adjust it.'**
  String get commandIntro;

  /// No description provided for @commandOneLine.
  ///
  /// In en, this message translates to:
  /// **'One line'**
  String get commandOneLine;

  /// No description provided for @commandExplained.
  ///
  /// In en, this message translates to:
  /// **'Explained'**
  String get commandExplained;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options…'**
  String get moreOptions;

  /// No description provided for @optionCodecTitle.
  ///
  /// In en, this message translates to:
  /// **'Editing format'**
  String get optionCodecTitle;

  /// No description provided for @cmdHideBanner.
  ///
  /// In en, this message translates to:
  /// **'Do not print version information'**
  String get cmdHideBanner;

  /// No description provided for @cmdSeek.
  ///
  /// In en, this message translates to:
  /// **'Start from this point of the video, in seconds'**
  String get cmdSeek;

  /// No description provided for @cmdInput.
  ///
  /// In en, this message translates to:
  /// **'The video to convert'**
  String get cmdInput;

  /// No description provided for @cmdLength.
  ///
  /// In en, this message translates to:
  /// **'Convert only this many seconds'**
  String get cmdLength;

  /// No description provided for @cmdKeepPicture.
  ///
  /// In en, this message translates to:
  /// **'Take the picture from the original'**
  String get cmdKeepPicture;

  /// No description provided for @cmdKeepSound.
  ///
  /// In en, this message translates to:
  /// **'Take every sound track, if there are any'**
  String get cmdKeepSound;

  /// No description provided for @cmdNoPicture.
  ///
  /// In en, this message translates to:
  /// **'Leave the picture out'**
  String get cmdNoPicture;

  /// No description provided for @cmdNoSound.
  ///
  /// In en, this message translates to:
  /// **'Leave the sound out'**
  String get cmdNoSound;

  /// No description provided for @cmdKeepMetadata.
  ///
  /// In en, this message translates to:
  /// **'Keep dates, titles and timecode'**
  String get cmdKeepMetadata;

  /// No description provided for @cmdDropMetadata.
  ///
  /// In en, this message translates to:
  /// **'Remove dates, titles and other details'**
  String get cmdDropMetadata;

  /// No description provided for @cmdPictureCopy.
  ///
  /// In en, this message translates to:
  /// **'Picture: copy as it is, no quality loss'**
  String get cmdPictureCopy;

  /// No description provided for @cmdPictureEncoder.
  ///
  /// In en, this message translates to:
  /// **'Picture: re-encode with this encoder'**
  String get cmdPictureEncoder;

  /// No description provided for @cmdSoundCopy.
  ///
  /// In en, this message translates to:
  /// **'Sound: copy as it is'**
  String get cmdSoundCopy;

  /// No description provided for @cmdSoundEncoder.
  ///
  /// In en, this message translates to:
  /// **'Sound: convert to this format'**
  String get cmdSoundEncoder;

  /// No description provided for @cmdSpeedPreset.
  ///
  /// In en, this message translates to:
  /// **'Effort: slower makes a smaller file at the same quality'**
  String get cmdSpeedPreset;

  /// No description provided for @cmdQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality target (for most encoders a lower number means better quality and a bigger file)'**
  String get cmdQuality;

  /// No description provided for @cmdProfile.
  ///
  /// In en, this message translates to:
  /// **'Variant of the format'**
  String get cmdProfile;

  /// No description provided for @cmdEncoderTuning.
  ///
  /// In en, this message translates to:
  /// **'Fine tuning of the encoder'**
  String get cmdEncoderTuning;

  /// No description provided for @cmdPixelFormat.
  ///
  /// In en, this message translates to:
  /// **'Colour precision of the picture'**
  String get cmdPixelFormat;

  /// No description provided for @cmdFilter.
  ///
  /// In en, this message translates to:
  /// **'Processing applied to the picture'**
  String get cmdFilter;

  /// No description provided for @cmdSoundBitrate.
  ///
  /// In en, this message translates to:
  /// **'Sound quality, as data per second'**
  String get cmdSoundBitrate;

  /// No description provided for @cmdConstantFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Make the frame timing even'**
  String get cmdConstantFrameRate;

  /// No description provided for @cmdFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frames per second'**
  String get cmdFrameRate;

  /// No description provided for @cmdKeyframeInterval.
  ///
  /// In en, this message translates to:
  /// **'A complete frame at least this often, for smooth scrubbing'**
  String get cmdKeyframeInterval;

  /// No description provided for @cmdPlayerTag.
  ///
  /// In en, this message translates to:
  /// **'Label that lets Apple players recognise the video'**
  String get cmdPlayerTag;

  /// No description provided for @cmdFastStart.
  ///
  /// In en, this message translates to:
  /// **'Put the index first, so playback can start while downloading'**
  String get cmdFastStart;

  /// No description provided for @cmdFastStartKeepingTags.
  ///
  /// In en, this message translates to:
  /// **'Put the index first, so playback can start while downloading, and keep the camera\'s make and model'**
  String get cmdFastStartKeepingTags;

  /// No description provided for @cmdLevelLimit.
  ///
  /// In en, this message translates to:
  /// **'Stay within what every player of video this size handles'**
  String get cmdLevelLimit;

  /// No description provided for @cmdDropTag.
  ///
  /// In en, this message translates to:
  /// **'Leave out the original\'s file type tag, which does not fit the new file'**
  String get cmdDropTag;

  /// No description provided for @cmdContainer.
  ///
  /// In en, this message translates to:
  /// **'File type of the result'**
  String get cmdContainer;

  /// No description provided for @cmdOutput.
  ///
  /// In en, this message translates to:
  /// **'Where the result is written'**
  String get cmdOutput;

  /// No description provided for @scenarioShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Send to a phone'**
  String get scenarioShareTitle;

  /// No description provided for @scenarioShareHint.
  ///
  /// In en, this message translates to:
  /// **'Small and plays on any phone, in Telegram and other messengers. In Telegram, send it as a file to keep this quality.'**
  String get scenarioShareHint;

  /// No description provided for @scenarioAudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Get the sound'**
  String get scenarioAudioTitle;

  /// No description provided for @scenarioAudioHint.
  ///
  /// In en, this message translates to:
  /// **'Saves the sound of a video as a separate file.'**
  String get scenarioAudioHint;

  /// No description provided for @scenarioPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove personal data'**
  String get scenarioPrivacyTitle;

  /// No description provided for @scenarioPrivacyHint.
  ///
  /// In en, this message translates to:
  /// **'Removes the hidden notes about place, date, camera and author before you share a video. What is seen and heard stays the same.'**
  String get scenarioPrivacyHint;

  /// No description provided for @scenarioRemuxTitle.
  ///
  /// In en, this message translates to:
  /// **'Change file type'**
  String get scenarioRemuxTitle;

  /// No description provided for @scenarioRemuxHint.
  ///
  /// In en, this message translates to:
  /// **'Puts the video into another kind of file in seconds, without touching the picture quality.'**
  String get scenarioRemuxHint;

  /// No description provided for @optionSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get optionSizeTitle;

  /// No description provided for @shareSmall.
  ///
  /// In en, this message translates to:
  /// **'Smaller'**
  String get shareSmall;

  /// No description provided for @shareStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get shareStandard;

  /// No description provided for @optionFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'File type'**
  String get optionFormatTitle;

  /// No description provided for @formatOriginal.
  ///
  /// In en, this message translates to:
  /// **'As it is'**
  String get formatOriginal;

  /// No description provided for @optionModeTitle.
  ///
  /// In en, this message translates to:
  /// **'How thoroughly'**
  String get optionModeTitle;

  /// No description provided for @modeQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get modeQuick;

  /// No description provided for @modeThorough.
  ///
  /// In en, this message translates to:
  /// **'Thorough'**
  String get modeThorough;

  /// No description provided for @modeThoroughHint.
  ///
  /// In en, this message translates to:
  /// **'Thorough rebuilds the picture and sound from scratch. It takes much longer and is the safest.'**
  String get modeThoroughHint;

  /// No description provided for @statusNoSound.
  ///
  /// In en, this message translates to:
  /// **'No sound in this file'**
  String get statusNoSound;

  /// No description provided for @statusCannotHold.
  ///
  /// In en, this message translates to:
  /// **'This file type cannot hold this video'**
  String get statusCannotHold;

  /// No description provided for @estimating.
  ///
  /// In en, this message translates to:
  /// **'measuring size…'**
  String get estimating;

  /// No description provided for @takesAbout.
  ///
  /// In en, this message translates to:
  /// **'takes about {time}'**
  String takesAbout(String time);

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as the computer'**
  String get languageSystem;

  /// No description provided for @lookTitle.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get lookTitle;

  /// No description provided for @lookCozy.
  ///
  /// In en, this message translates to:
  /// **'Cozy'**
  String get lookCozy;

  /// No description provided for @lookPro.
  ///
  /// In en, this message translates to:
  /// **'Professional'**
  String get lookPro;

  /// No description provided for @techPictureCopied.
  ///
  /// In en, this message translates to:
  /// **'picture copied as is'**
  String get techPictureCopied;

  /// No description provided for @techSoundCopied.
  ///
  /// In en, this message translates to:
  /// **'sound copied as is'**
  String get techSoundCopied;

  /// No description provided for @techNoSound.
  ///
  /// In en, this message translates to:
  /// **'no sound'**
  String get techNoSound;

  /// No description provided for @techNoReencode.
  ///
  /// In en, this message translates to:
  /// **'no re-encoding'**
  String get techNoReencode;

  /// No description provided for @techUpTo.
  ///
  /// In en, this message translates to:
  /// **'up to {lines}'**
  String techUpTo(String lines);

  /// No description provided for @inQueueCount.
  ///
  /// In en, this message translates to:
  /// **'{count} in queue'**
  String inQueueCount(int count);

  /// No description provided for @doneCount.
  ///
  /// In en, this message translates to:
  /// **'{count} done'**
  String doneCount(int count);

  /// No description provided for @videoDetails.
  ///
  /// In en, this message translates to:
  /// **'Video details'**
  String get videoDetails;

  /// No description provided for @recipeTitleSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{What to do with the selected video} other{What to do with {count} selected videos}}'**
  String recipeTitleSelected(int count);

  /// No description provided for @recipeTitleNone.
  ///
  /// In en, this message translates to:
  /// **'What to do'**
  String get recipeTitleNone;

  /// No description provided for @selectVideosHint.
  ///
  /// In en, this message translates to:
  /// **'Select videos on the left to choose what to do with them.'**
  String get selectVideosHint;

  /// No description provided for @convertTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get convertTitle;

  /// No description provided for @convertWhole.
  ///
  /// In en, this message translates to:
  /// **'Whole video'**
  String get convertWhole;

  /// No description provided for @convertSample.
  ///
  /// In en, this message translates to:
  /// **'10-second sample'**
  String get convertSample;

  /// No description provided for @addToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addToQueue;

  /// No description provided for @addAllToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add all ({count})'**
  String addAllToQueue(int count);

  /// No description provided for @alreadyQueued.
  ///
  /// In en, this message translates to:
  /// **'Already in the queue'**
  String get alreadyQueued;

  /// No description provided for @samplesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sample of 10 seconds} other{{count} samples of 10 seconds}}'**
  String samplesCount(int count);

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueTitle;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Choose videos and what to do, then press Add to queue. Converting starts by itself.'**
  String get queueEmpty;

  /// No description provided for @queuePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get queuePaused;

  /// No description provided for @jobWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get jobWaiting;

  /// No description provided for @pausedAt.
  ///
  /// In en, this message translates to:
  /// **'Paused at {percent}%'**
  String pausedAt(int percent);

  /// No description provided for @jobSkipped.
  ///
  /// In en, this message translates to:
  /// **'Nothing to do: already right'**
  String get jobSkipped;

  /// No description provided for @sampleChip.
  ///
  /// In en, this message translates to:
  /// **'Sample 10 s'**
  String get sampleChip;

  /// No description provided for @sampleResult.
  ///
  /// In en, this message translates to:
  /// **'Sample {size} · whole video about {fullSize}, about {time}'**
  String sampleResult(String size, String fullSize, String time);

  /// No description provided for @tookTime.
  ///
  /// In en, this message translates to:
  /// **'took {time}'**
  String tookTime(String time);

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @convertWholeVideo.
  ///
  /// In en, this message translates to:
  /// **'Convert whole video'**
  String get convertWholeVideo;

  /// No description provided for @originalDetails.
  ///
  /// In en, this message translates to:
  /// **'Details of the original'**
  String get originalDetails;

  /// No description provided for @resultDetails.
  ///
  /// In en, this message translates to:
  /// **'Details of the result'**
  String get resultDetails;

  /// No description provided for @useSettings.
  ///
  /// In en, this message translates to:
  /// **'Use these settings'**
  String get useSettings;

  /// No description provided for @removeFromList.
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get removeFromList;

  /// No description provided for @detailsViewEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get detailsViewEncoding;

  /// No description provided for @detailsViewMetadata.
  ///
  /// In en, this message translates to:
  /// **'All metadata'**
  String get detailsViewMetadata;

  /// No description provided for @detailsViewReport.
  ///
  /// In en, this message translates to:
  /// **'Full report'**
  String get detailsViewReport;

  /// No description provided for @noTags.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get noTags;

  /// No description provided for @groupFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get groupFile;

  /// No description provided for @groupVideo.
  ///
  /// In en, this message translates to:
  /// **'Video track {number}'**
  String groupVideo(int number);

  /// No description provided for @groupAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio track {number}'**
  String groupAudio(int number);

  /// No description provided for @groupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles {number}'**
  String groupSubtitle(int number);

  /// No description provided for @groupTimecode.
  ///
  /// In en, this message translates to:
  /// **'Timecode'**
  String get groupTimecode;

  /// No description provided for @groupData.
  ///
  /// In en, this message translates to:
  /// **'Data track {number}'**
  String groupData(int number);

  /// No description provided for @groupAttachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment {number}'**
  String groupAttachment(int number);

  /// No description provided for @groupChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get groupChapters;

  /// No description provided for @groupChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter {number}'**
  String groupChapter(int number);

  /// No description provided for @fieldContainer.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get fieldContainer;

  /// No description provided for @fieldSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get fieldSize;

  /// No description provided for @fieldDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get fieldDuration;

  /// No description provided for @fieldBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get fieldBitrate;

  /// No description provided for @fieldTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get fieldTracks;

  /// No description provided for @fieldCodec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get fieldCodec;

  /// No description provided for @fieldResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get fieldResolution;

  /// No description provided for @fieldAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get fieldAspectRatio;

  /// No description provided for @fieldFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get fieldFrameRate;

  /// No description provided for @fieldBitDepth.
  ///
  /// In en, this message translates to:
  /// **'Bit depth'**
  String get fieldBitDepth;

  /// No description provided for @fieldChroma.
  ///
  /// In en, this message translates to:
  /// **'Chroma subsampling'**
  String get fieldChroma;

  /// No description provided for @fieldPixelFormat.
  ///
  /// In en, this message translates to:
  /// **'Pixel format'**
  String get fieldPixelFormat;

  /// No description provided for @fieldColorPrimaries.
  ///
  /// In en, this message translates to:
  /// **'Colour primaries'**
  String get fieldColorPrimaries;

  /// No description provided for @fieldColorTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get fieldColorTransfer;

  /// No description provided for @fieldColorMatrix.
  ///
  /// In en, this message translates to:
  /// **'Matrix'**
  String get fieldColorMatrix;

  /// No description provided for @fieldColorRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get fieldColorRange;

  /// No description provided for @fieldHdr.
  ///
  /// In en, this message translates to:
  /// **'HDR'**
  String get fieldHdr;

  /// No description provided for @fieldMasteringDisplay.
  ///
  /// In en, this message translates to:
  /// **'Mastering display'**
  String get fieldMasteringDisplay;

  /// No description provided for @fieldLightLevel.
  ///
  /// In en, this message translates to:
  /// **'Light level'**
  String get fieldLightLevel;

  /// No description provided for @fieldScanType.
  ///
  /// In en, this message translates to:
  /// **'Scan type'**
  String get fieldScanType;

  /// No description provided for @fieldRotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get fieldRotation;

  /// No description provided for @fieldFrames.
  ///
  /// In en, this message translates to:
  /// **'Frames'**
  String get fieldFrames;

  /// No description provided for @fieldChannels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get fieldChannels;

  /// No description provided for @fieldSampleRate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get fieldSampleRate;

  /// No description provided for @fieldSampleFormat.
  ///
  /// In en, this message translates to:
  /// **'Sample format'**
  String get fieldSampleFormat;

  /// No description provided for @fieldLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get fieldLanguage;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldDefaultTrack.
  ///
  /// In en, this message translates to:
  /// **'Default track'**
  String get fieldDefaultTrack;

  /// No description provided for @fieldTimecode.
  ///
  /// In en, this message translates to:
  /// **'Timecode'**
  String get fieldTimecode;

  /// No description provided for @fieldFileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fieldFileName;

  /// No description provided for @fieldChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get fieldChapter;

  /// No description provided for @noteVariable.
  ///
  /// In en, this message translates to:
  /// **'variable'**
  String get noteVariable;

  /// No description provided for @noteProgressive.
  ///
  /// In en, this message translates to:
  /// **'progressive'**
  String get noteProgressive;

  /// No description provided for @noteInterlaced.
  ///
  /// In en, this message translates to:
  /// **'interlaced'**
  String get noteInterlaced;

  /// No description provided for @noteNotStated.
  ///
  /// In en, this message translates to:
  /// **'not stated'**
  String get noteNotStated;

  /// No description provided for @noteYes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get noteYes;

  /// No description provided for @noteNo.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get noteNo;

  /// Application name shown in the window title.
  ///
  /// In en, this message translates to:
  /// **'VidCtrl'**
  String get appTitle;

  /// No description provided for @noteVariableFrameRate.
  ///
  /// In en, this message translates to:
  /// **'Uneven frame timing will be fixed.'**
  String get noteVariableFrameRate;

  /// No description provided for @noteHevc422.
  ///
  /// In en, this message translates to:
  /// **'This recording format only plays in Resolve with a recent NVIDIA card.'**
  String get noteHevc422;

  /// No description provided for @noteExperimentalAv1.
  ///
  /// In en, this message translates to:
  /// **'Smallest files are harder to edit smoothly.'**
  String get noteExperimentalAv1;

  /// No description provided for @noteHdrToneMapped.
  ///
  /// In en, this message translates to:
  /// **'Very bright colours will be adjusted to look right on any screen.'**
  String get noteHdrToneMapped;

  /// No description provided for @noteHdrNotConverted.
  ///
  /// In en, this message translates to:
  /// **'This video uses extra-bright colours that may look washed out on a phone.'**
  String get noteHdrNotConverted;

  /// No description provided for @noteAudioConvertedToFit.
  ///
  /// In en, this message translates to:
  /// **'The sound will be converted to fit this file type.'**
  String get noteAudioConvertedToFit;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @convertSampleShort.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get convertSampleShort;

  /// No description provided for @sampleFirst.
  ///
  /// In en, this message translates to:
  /// **'first 10 s'**
  String get sampleFirst;

  /// No description provided for @sampleMiddle.
  ///
  /// In en, this message translates to:
  /// **'middle 10 s'**
  String get sampleMiddle;

  /// No description provided for @personalTag.
  ///
  /// In en, this message translates to:
  /// **'Personal detail: who, where, when or with what the video was made'**
  String get personalTag;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
