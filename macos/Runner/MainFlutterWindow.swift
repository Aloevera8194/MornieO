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

  /// The full window's frame and minimum size while the mini player shows.
  private var miniPlayerRestore: (frame: NSRect, minSize: NSSize)?

  /// Where the mini player last sat, by its top-left corner.
  private static let miniPlayerOriginKey = "MornyeMiniPlayerTopLeft"

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

    // Quitting from the mini player leaves the full window for the next
    // launch to restore.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.closeMiniPlayer(animate: false)
    }
  }

  /// Shrinks the window into a small floating panel of [size], or resizes
  /// the panel when it already shows. It stays above other windows and on
  /// every Space, keeps its top-left corner when it resizes, and opens
  /// where it last sat (first at the top right of the screen).
  private func openMiniPlayer(size: NSSize) -> Bool {
    if styleMask.contains(.fullScreen) { return false }
    let opening = miniPlayerRestore == nil
    if opening {
      miniPlayerRestore = (frame, contentMinSize)
      styleMask.remove(.resizable)
      level = .floating
      collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
      for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        standardWindowButton(button)?.isHidden = true
      }
    }
    contentMinSize = size
    var target = frameRect(forContentRect: NSRect(origin: .zero, size: size))
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
    var topLeft: NSPoint
    if !opening {
      topLeft = NSPoint(x: frame.minX, y: frame.maxY)
    } else if let saved = UserDefaults.standard.string(forKey: Self.miniPlayerOriginKey) {
      topLeft = NSPointFromString(saved)
    } else {
      topLeft = NSPoint(x: visible.maxX - target.width - 16, y: visible.maxY - 16)
    }
    // Keep the whole panel on the screen it opens on.
    topLeft.x = min(max(topLeft.x, visible.minX), visible.maxX - target.width)
    topLeft.y = min(max(topLeft.y, visible.minY + target.height), visible.maxY)
    target.origin = NSPoint(x: topLeft.x, y: topLeft.y - target.height)
    setFrame(target, display: true, animate: true)
    return true
  }

  /// Returns the window to the size, place and behavior it had before the
  /// mini player.
  private func closeMiniPlayer(animate: Bool) {
    guard let restore = miniPlayerRestore else { return }
    miniPlayerRestore = nil
    UserDefaults.standard.set(
      NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)),
      forKey: Self.miniPlayerOriginKey
    )
    level = .normal
    collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
    styleMask.insert(.resizable)
    contentMinSize = restore.minSize
    setFrame(restore.frame, display: true, animate: animate)
    for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      standardWindowButton(button)?.isHidden = false
    }
    layoutWindowControls()
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
      case "openMiniPlayer":
        let args = call.arguments as? [String: Any]
        let width = (args?["width"] as? NSNumber)?.doubleValue ?? 360
        let height = (args?["height"] as? NSNumber)?.doubleValue ?? 140
        result(self.openMiniPlayer(size: NSSize(width: width, height: height)))
      case "closeMiniPlayer":
        self.closeMiniPlayer(animate: true)
        result(nil)
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
