import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "GPU Playground"
    self.minSize = NSSize(width: 980, height: 640)
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.center()

    for screen in NSScreen.screens {
      NSLog("GPU Playground screen: \(screen.localizedName) "
        + "maxFPS=\(screen.maximumFramesPerSecond) scale=\(screen.backingScaleFactor)")
    }
    // Opt-in: open on the highest-refresh-rate screen (e.g. the built-in
    // ProMotion panel) instead of the default screen. Done after launch
    // settles so AppKit's frame constraining cannot bounce it back.
    if ProcessInfo.processInfo.environment["GPU_PLAYGROUND_PROMOTION"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self,
              let fast = NSScreen.screens.max(by: {
                $0.maximumFramesPerSecond < $1.maximumFramesPerSecond
              }),
              fast.maximumFramesPerSecond > 60 else { return }
        let area = fast.visibleFrame
        let size = self.frame.size
        let target = NSRect(
          x: area.midX - size.width / 2,
          y: area.midY - size.height / 2,
          width: size.width,
          height: size.height)
        self.setFrame(target, display: true)
        NSLog("GPU Playground: requested move to \(fast.localizedName) \(target)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          guard let self else { return }
          NSLog("GPU Playground: now on \(self.screen?.localizedName ?? "nil") "
            + "scale=\(self.backingScaleFactor) frame=\(self.frame)")
        }
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
