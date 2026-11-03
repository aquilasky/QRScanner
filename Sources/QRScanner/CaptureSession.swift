import AppKit
import ScreenCaptureKit

struct DisplaySnapshot {
    let frame: CGRect
    let image: CGImage
}

enum CaptureError: LocalizedError {
    case noDisplay, emptySelection
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "无法读取显示器，请检查屏幕录制权限。"
        case .emptySelection: return "选区太小或不在可捕获的显示器上，请重新选择。"
        }
    }
}

@MainActor
final class CaptureSession {
    private var overlays: [NSWindow] = []
    private var snapshots: [DisplaySnapshot] = []
    private var candidates: [WindowCandidate] = []
    private var completion: ((Result<CGImage, Error>?) -> Void)?
    private var keyMonitor: Any?

    func start(completion: @escaping (Result<CGImage, Error>?) -> Void) async throws {
        self.completion = completion
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let screens = NSScreen.screens
        guard let main = screens.first else { throw CaptureError.noDisplay }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }
        // CoreGraphics lists windows front to back, unlike the shareable-content array.
        let ordered = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                       as? [[String: Any]]) ?? []
        let available = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        candidates = ordered.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let window = available[number.uint32Value], window.windowLayer == 0,
                  window.owningApplication?.processID != ownPID,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  window.frame.width > 1, window.frame.height > 1 else { return nil }
            let owner = window.owningApplication?.applicationName ?? "窗口"
            let name = window.title.flatMap { $0.isEmpty ? nil : $0 }
            return WindowCandidate(id: window.windowID,
                frame: ScanGeometry.appKitRect(window.frame, mainScreenTop: main.frame.maxY),
                title: name.map { "\(owner) — \($0)" } ?? owner)
        }
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else {
                throw CaptureError.noDisplay
            }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            snapshots.append(DisplaySnapshot(frame: screen.frame, image: image))
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        NSApp.activate(ignoringOtherApps: true)
        for snapshot in snapshots {
            let window = CaptureOverlayWindow(contentRect: snapshot.frame, styleMask: .borderless,
                                             backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            let view = CaptureOverlayView(snapshot: snapshot, candidates: candidates)
            view.onSelect = { [weak self] rect in self?.select(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            overlays.append(window)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(nil); return nil }
            return event
        }
    }

    func cancel() { finish(nil) }

    private func select(_ rect: CGRect) {
        do { finish(.success(try composite(rect))) }
        catch { finish(.failure(error)) }
    }

    private func composite(_ region: CGRect) throws -> CGImage {
        let pieces = snapshots.filter { !$0.frame.intersection(region).isNull }
        guard region.width >= 2, region.height >= 2, !pieces.isEmpty else { throw CaptureError.emptySelection }
        let scale = pieces.map { CGFloat($0.image.width) / $0.frame.width }.max() ?? 1
        guard let context = CGContext(data: nil, width: Int(ceil(region.width * scale)),
            height: Int(ceil(region.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureError.emptySelection
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        for piece in pieces {
            let intersection = region.intersection(piece.frame)
            let crop = ScanGeometry.pixelCrop(region: region, screen: piece.frame,
                                             width: piece.image.width, height: piece.image.height)
            guard let image = piece.image.cropping(to: crop) else { throw CaptureError.emptySelection }
            let target = CGRect(x: (intersection.minX - region.minX) * scale,
                                y: (intersection.minY - region.minY) * scale,
                                width: intersection.width * scale, height: intersection.height * scale)
            context.draw(image, in: target)
        }
        guard let image = context.makeImage() else { throw CaptureError.emptySelection }
        return image
    }

    private func finish(_ result: Result<CGImage, Error>?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        overlays.forEach { $0.orderOut(nil); $0.close() }
        overlays.removeAll()
        snapshots.removeAll()
        candidates.removeAll()
        let handler = completion
        completion = nil
        handler?(result)
    }
}

private final class CaptureOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class CaptureOverlayView: NSView {
    let snapshot: DisplaySnapshot
    let candidates: [WindowCandidate]
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var anchor: CGPoint?
    private var dragged = false
    private var selection: CGRect = .zero

    init(snapshot: DisplaySnapshot, candidates: [WindowCandidate]) {
        self.snapshot = snapshot
        self.candidates = candidates
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        updateHover(NSEvent.mouseLocation)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func globalPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
    }
    private func updateHover(_ point: CGPoint) {
        let candidate = ScanGeometry.window(at: point, candidates: candidates)
        selection = candidate?.frame ?? snapshot.frame
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { if anchor == nil { updateHover(globalPoint(event)) } }
    override func mouseDown(with event: NSEvent) {
        anchor = globalPoint(event)
        dragged = false
        updateHover(globalPoint(event))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let end = globalPoint(event)
        if ScanGeometry.isDrag(from: anchor, to: end) { dragged = true }
        if dragged {
            selection = ScanGeometry.region(from: anchor, to: end, within: snapshot.frame)
            needsDisplay = true
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard anchor != nil else { return }
        if dragged, let anchor {
            selection = ScanGeometry.region(from: anchor, to: globalPoint(event), within: snapshot.frame)
        }
        anchor = nil
        onSelect?(selection)
    }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: snapshot.image, size: bounds.size).draw(in: bounds)
        let selected = local(selection).intersection(bounds)
        let mask = NSBezierPath(rect: bounds)
        if !selected.isNull { mask.appendRect(selected) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.38).setFill()
        mask.fill()
        if !selected.isNull {
            NSColor.systemGreen.setStroke()
            let outline = NSBezierPath(rect: selected.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }
    }
}
