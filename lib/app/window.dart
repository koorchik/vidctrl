import 'dart:ui';

/// The size the window opens at. Both sizes are what the app has inside
/// the window, without its title bar (`main.dart` adds it on macOS).
const defaultWindowSize = Size(1180, 800);

/// The smallest the window can be made. The "What to do" panel is designed
/// to show everything without scrolling at this size; a test checks every
/// goal and option against it.
const minimumWindowSize = Size(960, 660);
