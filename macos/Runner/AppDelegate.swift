import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    #if !DEBUG
      // macOS only keeps one instance per app copy. With a second copy (an
      // old download next to /Applications, a mounted dmg), a notification or
      // URL can start it too; hand over to the running instance instead.
      if let bundleId = Bundle.main.bundleIdentifier,
        let running = NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleId
        ).first(where: { $0 != NSRunningApplication.current })
      {
        running.activate()
        exit(0)
      }
    #endif
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
