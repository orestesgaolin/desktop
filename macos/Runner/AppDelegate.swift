import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine?
  private var edgeWindowChannel: FlutterMethodChannel?
  private weak var edgeWindow: NSWindow?
  private var edgeSide = "right"
  private var edgeHitTestTimer: Timer?
  private var edgeIsDragging = false
  private var edgeSawMouseButtonDown = false
  private var edgeDragStartMouse: NSPoint?
  private var edgeDragStartOrigin: NSPoint?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // The windowing API must enable multiview before any Flutter view
    // controller exists. Start the engine headlessly; WindowController in
    // Dart creates the main window and any detached browser tabs.
    let engine = FlutterEngine(name: "gpu-playground", project: nil)
    self.engine = engine
    edgeWindowChannel = FlutterMethodChannel(
      name: "gpu_playground/edge_window",
      binaryMessenger: engine.binaryMessenger)
    edgeWindowChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "dock":
        guard let side = call.arguments as? String else {
          result(FlutterError(code: "arguments", message: "Missing dock side", details: nil))
          return
        }
        edgeSide = side
        dockEdgeWindow(side: side)
        result(nil)
      case "beginDrag":
        beginEdgeWindowDrag()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(registerPluginsAfterFirstWindow),
      name: NSWindow.didBecomeKeyNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenParametersChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil)
    engine.run(withEntrypoint: nil)
  }

  /// Flutter owns this regular top-level window. AppKit supplies the clear,
  /// borderless shell and the absolute screen-space origin.
  private func dockEdgeWindow(side: String, attempt: Int = 0) {
    guard let parent = NSApp.windows.first(where: { $0.title == "Flutter GPU Playground" }) else {
      retryDock(side: side, attempt: attempt)
      return
    }

    let currentPopup = edgeWindow?.isVisible == true ? edgeWindow : nil
    let popup = currentPopup ?? NSApp.windows.first(where: {
      $0.title == "Floating frame"
        && $0.contentViewController is FlutterViewController
    })
    guard let popup else {
      retryDock(side: side, attempt: attempt)
      return
    }
    guard popup.frame.width >= 379, popup.frame.height >= 579 else {
      retryDock(side: side, attempt: attempt)
      return
    }

    edgeWindow = popup
    edgeSide = side
    popup.styleMask = [.borderless]
    popup.isOpaque = false
    popup.backgroundColor = .clear
    popup.hasShadow = false
    popup.level = .floating
    popup.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    popup.acceptsMouseMovedEvents = true
    popup.isMovable = false
    popup.isMovableByWindowBackground = false
    popup.setContentSize(NSSize(width: 380, height: 580))
    if let flutterController = popup.contentViewController as? FlutterViewController {
      flutterController.backgroundColor = .clear
    }
    popup.orderFrontRegardless()
    startEdgeHitTesting()

    // Always follow the display containing the presentation. A newly-created
    // top-level window may otherwise report whichever display AppKit chose for
    // its provisional frame.
    guard let screen = targetEdgeScreen(parent: parent) else { return }
    let area = screen.visibleFrame
    let origin = NSPoint(
      x: side == "left" ? area.minX : area.maxX - popup.frame.width,
      y: area.midY - popup.frame.height / 2)
    popup.setFrameOrigin(origin)
    publishEdgeWindowInfo(popup)
  }

  private func retryDock(side: String, attempt: Int) {
    guard attempt < 12 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.dockEdgeWindow(side: side, attempt: attempt + 1)
    }
  }

  private func beginEdgeWindowDrag() {
    guard let popup = edgeWindow else { return }
    edgeIsDragging = true
    edgeSawMouseButtonDown = NSEvent.pressedMouseButtons & 1 != 0
    edgeDragStartMouse = NSEvent.mouseLocation
    edgeDragStartOrigin = popup.frame.origin
    popup.ignoresMouseEvents = false
  }

  private func finishEdgeWindowDrag() -> String? {
    guard edgeIsDragging else { return edgeSide }
    updateEdgeWindowDragPosition()
    edgeIsDragging = false
    edgeSawMouseButtonDown = false
    edgeDragStartMouse = nil
    edgeDragStartOrigin = nil
    return snapEdgeWindowToClosestEdge()
  }

  private func updateEdgeWindowDragPosition() {
    guard
      edgeIsDragging,
      let popup = edgeWindow,
      let startMouse = edgeDragStartMouse,
      let startOrigin = edgeDragStartOrigin
    else { return }
    let mouse = NSEvent.mouseLocation
    popup.setFrameOrigin(NSPoint(
      x: startOrigin.x + mouse.x - startMouse.x,
      y: startOrigin.y + mouse.y - startMouse.y))
  }

  private func snapEdgeWindowToClosestEdge() -> String? {
    guard let popup = edgeWindow, let screen = popup.screen ?? NSScreen.main else { return nil }
    let area = screen.visibleFrame
    let distanceToLeft = abs(popup.frame.minX - area.minX)
    let distanceToRight = abs(area.maxX - popup.frame.maxX)
    let side = distanceToLeft <= distanceToRight ? "left" : "right"
    edgeSide = side

    let target = NSPoint(
      x: side == "left" ? area.minX : area.maxX - popup.frame.width,
      y: min(max(popup.frame.origin.y, area.minY), area.maxY - popup.frame.height))
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      popup.animator().setFrameOrigin(target)
    }, completionHandler: { [weak self, weak popup] in
      guard let self, let popup else { return }
      self.publishEdgeWindowInfo(popup)
    })
    edgeWindowChannel?.invokeMethod("didSnap", arguments: side)
    return side
  }

  private func publishEdgeWindowInfo(_ popup: NSWindow) {
    guard let screen = popup.screen ?? NSScreen.main else { return }
    edgeWindowChannel?.invokeMethod("didUpdateWindow", arguments: [
      "screenName": screen.localizedName,
      "x": Int(popup.frame.origin.x.rounded()),
      "y": Int(popup.frame.origin.y.rounded()),
    ])
  }

  private func targetEdgeScreen(parent: NSWindow) -> NSScreen? {
    let builtIn = NSScreen.screens.first { screen in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
      else {
        return false
      }
      return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
    return builtIn ?? parent.screen ?? NSScreen.main
  }

  private func startEdgeHitTesting() {
    guard edgeHitTestTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.updateEdgeHitTesting()
    }
    edgeHitTestTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  /// Native window hit testing is rectangular. While the pointer is over a
  /// clear part of the Flutter clip, ignore events for the whole window so the
  /// underlying application receives clicks and context menus.
  private func updateEdgeHitTesting() {
    guard let popup = edgeWindow, popup.isVisible else {
      edgeHitTestTimer?.invalidate()
      edgeHitTestTimer = nil
      edgeWindow = nil
      return
    }

    if edgeIsDragging {
      if NSEvent.pressedMouseButtons & 1 != 0 {
        edgeSawMouseButtonDown = true
        updateEdgeWindowDragPosition()
      } else if edgeSawMouseButtonDown {
        _ = finishEdgeWindowDrag()
      }
      popup.ignoresMouseEvents = false
      return
    }

    let mouse = NSEvent.mouseLocation
    guard popup.frame.contains(mouse) else {
      popup.ignoresMouseEvents = false
      return
    }
    let localPoint = CGPoint(
      x: mouse.x - popup.frame.minX,
      y: popup.frame.maxY - mouse.y)
    let controlRegionIsSafe = edgeSide == "right"
      ? localPoint.x >= 82
      : localPoint.x <= popup.frame.width - 82
    let visiblePixel = edgeWindowPath(
      size: popup.frame.size,
      side: edgeSide).contains(localPoint)
    popup.ignoresMouseEvents = !controlRegionIsSafe && !visiblePixel
  }

  /// Mirrors EdgeWaveClipper's top-left coordinate path for native hit tests.
  private func edgeWindowPath(size: CGSize, side: String) -> CGPath {
    let path = CGMutablePath()
    if side == "right" {
      path.move(to: CGPoint(x: 94, y: 0))
      path.addCurve(
        to: CGPoint(x: 54, y: 205),
        control1: CGPoint(x: 30, y: 75),
        control2: CGPoint(x: 106, y: 132))
      path.addCurve(
        to: CGPoint(x: 55, y: 397),
        control1: CGPoint(x: 10, y: 270),
        control2: CGPoint(x: 104, y: 327))
      path.addCurve(
        to: CGPoint(x: 72, y: size.height),
        control1: CGPoint(x: 18, y: 455),
        control2: CGPoint(x: 92, y: 512))
      path.addLine(to: CGPoint(x: size.width, y: size.height))
      path.addLine(to: CGPoint(x: size.width, y: 0))
    } else {
      path.move(to: CGPoint(x: size.width - 94, y: 0))
      path.addCurve(
        to: CGPoint(x: size.width - 54, y: 205),
        control1: CGPoint(x: size.width - 30, y: 75),
        control2: CGPoint(x: size.width - 106, y: 132))
      path.addCurve(
        to: CGPoint(x: size.width - 55, y: 397),
        control1: CGPoint(x: size.width - 10, y: 270),
        control2: CGPoint(x: size.width - 104, y: 327))
      path.addCurve(
        to: CGPoint(x: size.width - 72, y: size.height),
        control1: CGPoint(x: size.width - 18, y: 455),
        control2: CGPoint(x: size.width - 92, y: 512))
      path.addLine(to: CGPoint(x: 0, y: size.height))
      path.addLine(to: CGPoint(x: 0, y: 0))
    }
    path.closeSubpath()
    return path
  }

  @objc private func screenParametersChanged() {
    if edgeWindow != nil {
      dockEdgeWindow(side: edgeSide)
    }
  }

  @objc private func registerPluginsAfterFirstWindow(_ notification: Notification) {
    guard let engine else { return }
    NotificationCenter.default.removeObserver(
      self, name: NSWindow.didBecomeKeyNotification, object: nil)
    // Some existing plugins still assume a Flutter view already exists.
    // Register them only after WindowController has enabled multiview and
    // created the first view. They remain available to every later window.
    RegisterGeneratedPlugins(registry: engine)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
