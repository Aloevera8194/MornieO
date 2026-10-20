import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mornye/utils/desktop_platform.dart';

/// Overrides [desktopTitleBarInContent] in tests.
bool? debugDesktopTitleBarInContentOverride;

/// Whether the window content reaches under a transparent title bar, with
/// the window controls over the top of the sidebar, as in Music. The macOS
/// window does this (`macos/Runner/MainFlutterWindow.swift`); Windows and
/// Linux keep their native frame.
bool get desktopTitleBarInContent =>
    debugDesktopTitleBarInContentOverride ??
    (isDesktopPlatform && Platform.isMacOS);

/// Height of the title bar row at the top of the window content. The
/// traffic lights sit centered in it, so the sidebar starts below it. Keep
/// in sync with `titleBarHeight` in `MainFlutterWindow.swift`.
const double desktopTitleBarHeight = 52;

/// Width the traffic lights take at the leading edge of the title bar row.
const double desktopWindowControlsWidth = 78;

const _windowChannel = MethodChannel('com.zarz.mornye/window');

Future<void> _invokeWindow(String method) async {
  try {
    await _windowChannel.invokeMethod<void>(method);
  } on MissingPluginException {
    // Only the macOS runner draws content under its title bar.
  } on PlatformException {
    // The window may close while the call is in flight.
  }
}

/// Part of the title bar row: dragging it moves the window and, with
/// [zoomOnDoubleClick], a double click zooms it like a native title bar.
/// Widgets inside or behind it keep their clicks. Without a title bar in
/// the content ([desktopTitleBarInContent]) it only shows [child].
class DesktopWindowDragArea extends StatefulWidget {
  const DesktopWindowDragArea({
    super.key,
    this.child,
    this.zoomOnDoubleClick = false,
  });

  final Widget? child;

  /// Zooms (or minimizes, per the system setting) on a double click. Leave
  /// it off where buttons share the area, so their clicks never wait for a
  /// second one.
  final bool zoomOnDoubleClick;

  @override
  State<DesktopWindowDragArea> createState() => _DesktopWindowDragAreaState();
}

class _DesktopWindowDragAreaState extends State<DesktopWindowDragArea> {
  Duration? _lastDown;
  Offset? _lastPosition;

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final lastDown = _lastDown;
    final lastPosition = _lastPosition;
    if (lastDown != null &&
        lastPosition != null &&
        event.timeStamp - lastDown <= kDoubleTapTimeout &&
        (event.position - lastPosition).distance <= kDoubleTapSlop) {
      _lastDown = null;
      _lastPosition = null;
      unawaited(_invokeWindow('titleBarDoubleClick'));
      return;
    }
    _lastDown = event.timeStamp;
    _lastPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (!desktopTitleBarInContent) return child ?? const SizedBox.shrink();
    Widget area = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => unawaited(_invokeWindow('startDrag')),
      child: child,
    );
    if (widget.zoomOnDoubleClick) {
      area = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: area,
      );
    }
    return area;
  }
}
