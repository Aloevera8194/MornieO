import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Height of the title bar row the Flutter content leaves for the window
  /// controls. Keep in sync with `desktopTitleBarHeight` in
  /// lib/widgets/desktop/desktop_window.dart.
  private static let titleBarHeight: CGFloat = 52

  /// Distance from the leading window edge to the close button.
  private static let windowControlsInset: CGFloat = 20

  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.contentMinSize = NSSize(width: 800, height: 600)
    self.center()

    // Like Music, the content reaches the top of the window: the sidebar
    // runs under the traffic lights and the content pane's controls share
    // their row. Flutter draws drag areas there (DesktopWindowDragArea).
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWindowChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()

    // AppKit puts the title bar controls back after resizing, full screen
    // and key changes, so center them in the taller row again each time.
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification,
      NSWindow.didChangeBackingPropertiesNotification,
    ] {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(windowControlsNeedLayout),
        name: name,
        object: self
      )
    }
    layoutWindowControls()

    // Music swaps its lyrics panel for a full-window player in full screen,
    // so the Flutter side follows the window in and out of it.
    for (name, fullScreen) in [
      (NSWindow.willEnterFullScreenNotification, true),
      (NSWindow.didExitFullScreenNotification, false),
    ] {
      NotificationCenter.default.addObserver(
        forName: name,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.windowChannel?.invokeMethod("fullScreenChanged", arguments: fullScreen)
      }
    }
  }

  @objc private func windowControlsNeedLayout(_ notification: Notification) {
    layoutWindowControls()
  }

  /// Centers the traffic lights vertically in a [titleBarHeight] row.
  private func layoutWindowControls() {
    guard !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let miniaturize = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let titleBar = close.superview,
      let container = titleBar.superview
    else { return }
    let height = Self.titleBarHeight
    var containerFrame = container.frame
    containerFrame.size.height = height
    containerFrame.origin.y = frame.height - height
    container.frame = containerFrame
    titleBar.frame = container.bounds
    let spacing = miniaturize.frame.minX - close.frame.minX
    for (index, button) in [close, miniaturize, zoom].enumerated() {
      button.setFrameOrigin(
        NSPoint(
          x: Self.windowControlsInset + CGFloat(index) * spacing,
          y: ((height - button.frame.height) / 2).rounded()
        )
      )
    }
  }

  /// Window actions for the Flutter drag areas in the title bar row.
  private func registerWindowChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.zarz.mornye/window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "startDrag":
        if let event = self.currentEvent ?? NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "titleBarDoubleClick":
        self.performTitleBarDoubleClick()
        result(nil)
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    windowChannel = channel
  }

  /// Follows the Desktop & Dock setting for double-clicking a title bar.
  private func performTitleBarDoubleClick() {
    switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
    case "Minimize":
      performMiniaturize(nil)
    case "None":
      break
    default:
      performZoom(nil)
    }
  }
}
