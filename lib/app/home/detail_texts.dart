import '../../core/media/media_details.dart';
import '../../l10n/app_localizations.dart';

/// The words shown for the details of a video ("Video details"): the
/// engine knows its tracks, fields and notes only by code.

String groupTitle(AppLocalizations l10n, DetailGroup group, int number) =>
    switch (group) {
      DetailGroup.file => l10n.groupFile,
      DetailGroup.video => l10n.groupVideo(number),
      DetailGroup.audio => l10n.groupAudio(number),
      DetailGroup.subtitle => l10n.groupSubtitle(number),
      DetailGroup.timecode => l10n.groupTimecode,
      DetailGroup.data => l10n.groupData(number),
      DetailGroup.attachment => l10n.groupAttachment(number),
      DetailGroup.chapters => l10n.groupChapters,
    };

String fieldLabel(AppLocalizations l10n, DetailField field) => switch (field) {
  DetailField.container => l10n.fieldContainer,
  DetailField.size => l10n.fieldSize,
  DetailField.duration => l10n.fieldDuration,
  DetailField.bitrate => l10n.fieldBitrate,
  DetailField.tracks => l10n.fieldTracks,
  DetailField.codec => l10n.fieldCodec,
  DetailField.resolution => l10n.fieldResolution,
  DetailField.aspectRatio => l10n.fieldAspectRatio,
  DetailField.frameRate => l10n.fieldFrameRate,
  DetailField.bitDepth => l10n.fieldBitDepth,
  DetailField.chroma => l10n.fieldChroma,
  DetailField.pixelFormat => l10n.fieldPixelFormat,
  DetailField.colorPrimaries => l10n.fieldColorPrimaries,
  DetailField.colorTransfer => l10n.fieldColorTransfer,
  DetailField.colorMatrix => l10n.fieldColorMatrix,
  DetailField.colorRange => l10n.fieldColorRange,
  DetailField.hdr => l10n.fieldHdr,
  DetailField.masteringDisplay => l10n.fieldMasteringDisplay,
  DetailField.lightLevel => l10n.fieldLightLevel,
  DetailField.scanType => l10n.fieldScanType,
  DetailField.rotation => l10n.fieldRotation,
  DetailField.frames => l10n.fieldFrames,
  DetailField.channels => l10n.fieldChannels,
  DetailField.sampleRate => l10n.fieldSampleRate,
  DetailField.sampleFormat => l10n.fieldSampleFormat,
  DetailField.language => l10n.fieldLanguage,
  DetailField.title => l10n.fieldTitle,
  DetailField.defaultTrack => l10n.fieldDefaultTrack,
  DetailField.timecode => l10n.fieldTimecode,
  DetailField.fileName => l10n.fieldFileName,
  DetailField.chapter => l10n.fieldChapter,
};

/// The translated word, if any, followed by the technical value.
String rowValue(AppLocalizations l10n, DetailRow row) {
  final note = switch (row.note) {
    DetailNote.variable => l10n.noteVariable,
    DetailNote.progressive => l10n.noteProgressive,
    DetailNote.interlaced => l10n.noteInterlaced,
    DetailNote.notStated => l10n.noteNotStated,
    DetailNote.yes => l10n.noteYes,
    DetailNote.no => l10n.noteNo,
    null => null,
  };
  return [?note, if (row.value.isNotEmpty) row.value].join(': ');
}

/// The title of a section of tags: a numbered chapter, or the track or
/// file it belongs to.
String tagTitle(AppLocalizations l10n, TagSection section) =>
    section.group == DetailGroup.chapters
    ? l10n.groupChapter(section.number)
    : groupTitle(l10n, section.group, section.number);
