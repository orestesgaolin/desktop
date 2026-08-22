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
    // Opt-in window placement: GPU_PLAYGROUND_SCREEN=fast opens 1280x800 on
    // the highest-refresh screen (e.g. the built-in ProMotion panel);
    // =main opens 1280x800 on the main screen. GPU_PLAYGROUND_PROMOTION=1 is
    // the legacy spelling of =fast. Done after launch settles so AppKit's
    // frame constraining and state restoration cannot bounce it back.
    let env = ProcessInfo.processInfo.environment
    var screenChoice = env["GPU_PLAYGROUND_SCREEN"]
    if screenChoice == nil && env["GPU_PLAYGROUND_PROMOTION"] == "1" {
      screenChoice = "fast"
    }
    if let choice = screenChoice {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self else { return }
        let screen: NSScreen?
        switch choice {
        case "fast":
          screen = NSScreen.screens.max(by: {
            $0.maximumFramesPerSecond < $1.maximumFramesPerSecond
          })
        default:
          screen = NSScreen.main
        }
        guard let screen else { return }
        let area = screen.visibleFrame
        let target = NSRect(
          x: area.midX - 640, y: area.midY - 416, width: 1280, height: 832)
        self.setFrame(target, display: true)
        NSLog("GPU Playground: moved to \(screen.localizedName) \(target)")
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
