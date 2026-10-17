// Draws the application icon and writes it in the form each platform wants.
// The drawing in this file is the only source of the icon; the files it
// writes are committed, including the copy the app shows in its header.
//
//   flutter test tool/make_icons.dart
//
// It goes through `flutter test` because drawing needs Flutter's canvas, which
// `dart run` does not have. A sheet for looking at the result is written to
// build/icon_preview/.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _macosIcons = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
const _windowsIcon = 'windows/runner/resources/app_icon.ico';
const _linuxIcons = 'linux/runner/resources';

/// The copy the app shows beside its name, at four times its size on screen.
const _appIcon = 'assets/app_icon.png';
const _appIconSize = 96;
const _preview = 'build/icon_preview/icon.png';

/// The sizes `Contents.json` in the macOS icon set names.
const _macosSizes = [16, 32, 64, 128, 256, 512, 1024];

/// What Windows asks for at its display scales, from the title bar to the
/// large tiles.
const _windowsSizes = [16, 20, 24, 32, 40, 48, 64, 256];

/// Loaded by the Linux runner (`my_application.cc`), which names the same
/// sizes.
const _linuxSizes = [16, 32, 48, 64, 128, 256];

/// The icon is designed on a square of this side and scaled to each size.
const _grid = 1024.0;

/// The app's accent colour (`theme.dart`), lighter above and deeper below.
const _top = Color(0xFF7168F8);
const _bottom = Color(0xFF3D33C2);
const _white = Color(0xFFFFFFFF);

/// How the coloured square sits on the canvas.
enum _Frame {
  /// Apple's icon grid: the square takes 824 of 1024 and casts a soft shadow
  /// into the margin.
  macos(square: 824, shadow: true),

  /// Windows and Linux icons have no shadow of their own and fill the canvas
  /// but for a thin margin.
  filled(square: 944, shadow: false);

  const _Frame({required this.square, required this.shadow});

  final double square;
  final bool shadow;
}

/// A play triangle of the given [scale], its tip kept on the same line and
/// moved [left] so that the smaller ones sit inside the larger.
typedef _Step = ({double scale, double left, double opacity});

/// A video getting smaller: the same play triangle three times, each smaller
/// and brighter than the one before.
const _steps = <_Step>[
  (scale: 1.00, left: 0, opacity: 0.16),
  (scale: 0.70, left: 21, opacity: 0.32),
  (scale: 0.40, left: 110, opacity: 1),
];

/// Three shapes blur into one below about 24 pixels, so the smallest sizes
/// get two, with the solid one larger.
const _stepsWhenTiny = <_Step>[
  (scale: 1.00, left: 0, opacity: 0.30),
  (scale: 0.52, left: 92, opacity: 1),
];

const _tip = Offset(800, 512);
const _triangle = [Offset(232, 184), Offset(232, 840), _tip];
const _cornerRadius = 76.0;

void _paintIcon(Canvas canvas, int size, _Frame frame) {
  canvas.scale(size / _grid);
  final margin = (_grid - frame.square) / 2;
  final square = Path()
    ..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        Rect.fromLTWH(margin, margin, frame.square, frame.square),
        Radius.circular(frame.square * 0.225),
      ),
    );
  if (frame.shadow) {
    canvas.drawPath(
      square.shift(const Offset(0, 12)),
      Paint()
        ..color = const Color(0x52000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }
  canvas.drawPath(
    square,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(_grid * 0.25, margin),
        Offset(_grid * 0.75, _grid - margin),
        [_top, _bottom],
      ),
  );

  // The triangles are placed on the full grid and shrunk with the square.
  canvas.translate(margin, margin);
  canvas.scale(frame.square / _grid);
  for (final step in size <= 24 ? _stepsWhenTiny : _steps) {
    canvas.drawPath(
      _roundedPolygon([
        for (final point in _triangle)
          _tip + (point - _tip) * step.scale - Offset(step.left, 0),
      ], _cornerRadius * step.scale),
      Paint()..color = _white.withValues(alpha: step.opacity),
    );
  }
}

/// A polygon with every corner rounded to [radius].
Path _roundedPolygon(List<Offset> points, double radius) {
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final corner = points[i];
    final before = points[(i - 1 + points.length) % points.length] - corner;
    final after = points[(i + 1) % points.length] - corner;
    final toBefore = before / before.distance;
    final toAfter = after / after.distance;
    final angle = math.acos(
      toBefore.dx * toAfter.dx + toBefore.dy * toAfter.dy,
    );
    // The arc touches each side this far from the corner.
    final cut = radius / math.tan(angle / 2);
    final start = corner + toBefore * cut;
    final end = corner + toAfter * cut;
    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    final turn = toBefore.dy * toAfter.dx - toBefore.dx * toAfter.dy;
    path.arcToPoint(end, radius: Radius.circular(radius), clockwise: turn > 0);
  }
  return path..close();
}

Future<ui.Image> _render(int size, _Frame frame) {
  final recorder = ui.PictureRecorder();
  _paintIcon(Canvas(recorder), size, frame);
  return recorder.endRecording().toImage(size, size);
}

Future<Uint8List> _png(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Packs [images] into a Windows icon file. As in the icons Windows itself
/// ships, the 256-pixel image is stored as PNG and the smaller ones as plain
/// bitmaps, which every reader of the format understands.
Future<Uint8List> _ico(List<ui.Image> images) async {
  final pictures = [
    for (final image in images)
      image.width >= 256 ? await _png(image) : await _icoBitmap(image),
  ];
  const headerSize = 6;
  const entrySize = 16;
  final directory = ByteData(headerSize + entrySize * images.length)
    ..setUint16(2, 1, Endian.little) // an icon, not a cursor
    ..setUint16(4, images.length, Endian.little);
  var offset = directory.lengthInBytes;
  for (var i = 0; i < images.length; i++) {
    final entry = headerSize + entrySize * i;
    directory
      ..setUint8(entry, images[i].width % 256) // 0 stands for 256
      ..setUint8(entry + 1, images[i].height % 256)
      ..setUint16(entry + 4, 1, Endian.little) // colour planes
      ..setUint16(entry + 6, 32, Endian.little) // bits per pixel
      ..setUint32(entry + 8, pictures[i].length, Endian.little)
      ..setUint32(entry + 12, offset, Endian.little);
    offset += pictures[i].length;
  }
  final file = BytesBuilder()..add(directory.buffer.asUint8List());
  pictures.forEach(file.add);
  return file.toBytes();
}

/// One image as an icon file stores it: a bitmap header, the pixels as BGRA
/// from the bottom row up, then a one-bit mask of the transparent pixels.
Future<Uint8List> _icoBitmap(ui.Image image) async {
  final width = image.width;
  final height = image.height;
  final rgba = (await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  ))!;
  const headerSize = 40;
  final pixelsSize = width * height * 4;
  // Mask rows are padded to a multiple of four bytes.
  final maskRowSize = (width + 31) ~/ 32 * 4;
  final maskSize = maskRowSize * height;
  final out = ByteData(headerSize + pixelsSize + maskSize)
    ..setUint32(0, headerSize, Endian.little)
    ..setInt32(4, width, Endian.little)
    ..setInt32(8, height * 2, Endian.little) // pixels and mask together
    ..setUint16(12, 1, Endian.little) // colour planes
    ..setUint16(14, 32, Endian.little) // bits per pixel
    ..setUint32(20, pixelsSize + maskSize, Endian.little);
  for (var y = 0; y < height; y++) {
    final row = height - 1 - y;
    for (var x = 0; x < width; x++) {
      final from = (y * width + x) * 4;
      final to = headerSize + (row * width + x) * 4;
      final alpha = rgba.getUint8(from + 3);
      out
        ..setUint8(to, rgba.getUint8(from + 2))
        ..setUint8(to + 1, rgba.getUint8(from + 1))
        ..setUint8(to + 2, rgba.getUint8(from))
        ..setUint8(to + 3, alpha);
      if (alpha == 0) {
        final at = headerSize + pixelsSize + row * maskRowSize + x ~/ 8;
        out.setUint8(at, out.getUint8(at) | 0x80 >> x % 8);
      }
    }
  }
  return out.buffer.asUint8List();
}

/// Both frames at every size, on a light and a dark background, with the
/// small sizes enlarged below so their pixels can be judged.
Future<Uint8List> _previewSheet() async {
  const sizes = [256, 128, 64, 48, 32, 24, 16];
  const enlarged = [32, 24, 16];
  const gap = 20.0;
  const rowHeight = 256 + 2 * gap;
  const halfWidth = 760.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final pixels = Paint()..filterQuality = FilterQuality.none;
  const backgrounds = [Color(0xFFF1EFF7), Color(0xFF1D1B22)];
  for (var half = 0; half < backgrounds.length; half++) {
    final left = half * halfWidth;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, halfWidth, rowHeight * _Frame.values.length),
      Paint()..color = backgrounds[half],
    );
    for (final frame in _Frame.values) {
      final top = frame.index * rowHeight + gap;
      var x = left + gap;
      for (final size in sizes) {
        canvas.drawImage(await _render(size, frame), Offset(x, top), pixels);
        x += size + gap;
      }
      x = left + 256 + 2 * gap;
      for (final size in enlarged) {
        canvas.drawImageRect(
          await _render(size, frame),
          Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          Rect.fromLTWH(x, top + 144, 112, 112),
          pixels,
        );
        x += 112 + gap;
      }
    }
  }
  final sheet = await recorder.endRecording().toImage(
    (halfWidth * backgrounds.length).toInt(),
    (rowHeight * _Frame.values.length).toInt(),
  );
  return _png(sheet);
}

void _write(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void main() {
  test('writes the icon files of every platform', () async {
    for (final size in _macosSizes) {
      final image = await _render(size, _Frame.macos);
      _write('$_macosIcons/app_icon_$size.png', await _png(image));
    }
    _write(
      _windowsIcon,
      await _ico([
        for (final size in _windowsSizes) await _render(size, _Frame.filled),
      ]),
    );
    for (final size in _linuxSizes) {
      final image = await _render(size, _Frame.filled);
      _write('$_linuxIcons/app_icon_$size.png', await _png(image));
    }
    _write(_appIcon, await _png(await _render(_appIconSize, _Frame.filled)));
    _write(_preview, await _previewSheet());
  });
}
