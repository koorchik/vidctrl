// Written by tool/make_manual.dart from the English texts;
// run `flutter test tool/make_manual.dart` after changing them.
// dart format off
import 'manual.dart';

/// Every goal's English words, by preset id.
const manualGoalWords = <String, GoalWords>{
  'archive.master': (
    title: 'Archive',
    subtitle: 'no quality loss',
    hint: 'Camera videos take far less space and look the same as the originals. Dates, camera details, sound and colours are kept.',
    options: {
      'codec': (
        title: 'Format',
        hint: '',
        choices: {
          'av1': (label: 'Smallest file', hint: 'Plays on computers (Macs from M1) and newer devices: iPhone 15 Pro and later, TVs from about 2020.'),
          'hevc': (label: 'Works everywhere', hint: 'The same look in a file up to a third larger. Plays almost everywhere, older iPhones, Macs and TVs included.'),
        },
      ),
      'speed': (
        title: 'Speed',
        hint: '',
        choices: {
          'cpu': (label: 'Thorough', hint: 'The processor encodes: slower, and the file is the smallest.'),
          'gpu': (label: 'Fast', hint: 'The graphics card encodes: several times faster. Busy footage comes out the same size, calm footage up to 2.5 times larger.'),
        },
      ),
    },
  ),
  'space.small': (
    title: 'Save space',
    subtitle: 'good enough',
    hint: 'For call recordings and other videos kept just in case: much smaller files that are still good to watch. Fine details soften. At most 1080p and 30 frames a second: larger videos are reduced.',
    options: {
    },
  ),
  'resolve.studio': (
    title: 'Edit in DaVinci Resolve',
    subtitle: 'Resolve Studio',
    hint: 'Makes videos open with picture and sound in Resolve on Linux. Usually only the sound needs fixing, which takes seconds.',
    options: {
      'convertVideo': (
        title: 'Also convert the picture',
        hint: 'Turn on if videos play choppily, as they can without an NVIDIA graphics card.',
        choices: {
          'no': (label: 'no', hint: ''),
          'yes': (label: 'yes', hint: ''),
        },
      ),
      'quality': (
        title: 'File size',
        hint: '',
        choices: {
          'smallest': (label: 'Smallest', hint: ''),
          'smaller': (label: 'Smaller', hint: ''),
          'balanced': (label: 'Recommended', hint: ''),
          'best': (label: 'Best quality', hint: ''),
        },
      ),
      'codec': (
        title: 'Editing format',
        hint: '',
        choices: {
          'prores': (label: 'ProRes', hint: ''),
          'dnxhr': (label: 'DNxHR', hint: ''),
        },
      ),
    },
  ),
  'resolve.free': (
    title: 'Edit in DaVinci Resolve',
    subtitle: 'Free Resolve',
    hint: 'Makes videos open with picture and sound in Resolve on Linux. The picture is converted too. Files become much larger.',
    options: {
      'quality': (
        title: 'File size',
        hint: '',
        choices: {
          'smallest': (label: 'Smallest', hint: ''),
          'smaller': (label: 'Smaller', hint: ''),
          'balanced': (label: 'Recommended', hint: ''),
          'best': (label: 'Best quality', hint: ''),
        },
      ),
      'codec': (
        title: 'Editing format',
        hint: '',
        choices: {
          'prores': (label: 'ProRes', hint: ''),
          'dnxhr': (label: 'DNxHR', hint: ''),
        },
      ),
    },
  ),
  'audio.extract': (
    title: 'Get the sound',
    subtitle: '',
    hint: 'Saves the sound of a video as a separate file.',
    options: {
      'format': (
        title: 'File type',
        hint: '',
        choices: {
          'original': (label: 'As it is', hint: ''),
          'mp3': (label: 'MP3', hint: ''),
          'm4a': (label: 'M4A', hint: ''),
          'wav': (label: 'WAV', hint: ''),
          'flac': (label: 'FLAC', hint: ''),
        },
      ),
    },
  ),
  'privacy.clean': (
    title: 'Remove personal data',
    subtitle: '',
    hint: 'Removes the hidden notes about place, date, camera and author before you share a video. What is seen and heard stays the same.',
    options: {
      'mode': (
        title: 'How thoroughly',
        hint: 'Thorough rebuilds the picture and sound from scratch. It takes much longer and is the safest.',
        choices: {
          'quick': (label: 'Quick', hint: ''),
          'thorough': (label: 'Thorough', hint: ''),
        },
      ),
    },
  ),
  'remux.container': (
    title: 'Change file type',
    subtitle: '',
    hint: 'Puts the video into another kind of file in seconds, without touching the picture quality.',
    options: {
      'format': (
        title: 'File type',
        hint: '',
        choices: {
          'mp4': (label: 'MP4', hint: ''),
          'mkv': (label: 'MKV', hint: ''),
          'mov': (label: 'MOV', hint: ''),
        },
      ),
    },
  ),
};
