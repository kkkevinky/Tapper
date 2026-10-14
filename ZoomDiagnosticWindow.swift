import AppKit

/// Development-only menu entry. Posting a probe requires an explicit button
/// click; opening the window never injects input or changes user preferences.
@MainActor
final class ZoomDiagnosticWindow: NSWindowController {
    private let canvas = ZoomDiagnosticCanvas(frame: NSRect(x: 0, y: 0, width: 580, height: 350))
    private var probeGeneration = 0

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Zoom Diagnostics"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let button = NSButton(title: "Send a zoom probe in 3 seconds", target: self, action: #selector(probe))
        let note = NSTextField(wrappingLabelWithString: "Move the pointer onto the canvas or a target app after clicking. The probe sends one short pinch gesture. Physical finger direction must be checked separately.")
        let stack = NSStackView(views: [note, canvas, button])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        canvas.widthAnchor.constraint(equalToConstant: 580).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: 350).isActive = true
        window.contentView = stack
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    @objc private func probe() {
        probeGeneration += 1
        let generation = probeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.probeGeneration == generation else { return }
            let synthesizer = ZoomEventSynthesizer()
            let compatibility = ZoomScrollFilter.currentTarget()?.compatibility ?? .standard
            synthesizer.send(ZoomUpdate(phase: .began, magnification: 0), compatibility: compatibility)
            for step in 1...12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) / 60) {
                    synthesizer.tick()
                    synthesizer.send(ZoomUpdate(phase: step == 12 ? .ended : .changed,
                                                magnification: step == 12 ? 0 : 0.015))
                }
            }
        }
    }
}

@MainActor
private final class ZoomDiagnosticCanvas: NSView {
    private var scale: CGFloat = 1
    private var count = 0
    private var phase = "none"

    override func magnify(with event: NSEvent) {
        count += 1
        scale = min(4, max(0.25, scale * (1 + event.magnification)))
        phase = String(describing: event.phase)
        ZoomDiagnostics.log("received NSEvent magnification=\(event.magnification) phase=\(event.phase.rawValue)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.controlAccentColor.setFill()
        let size = 100 * scale
        NSBezierPath(roundedRect: NSRect(x: (bounds.width - size) / 2,
                                        y: (bounds.height - size) / 2, width: size, height: size),
                     xRadius: 12, yRadius: 12).fill()
        let text = "Received: \(count)   Scale: \(String(format: "%.2f", scale))   Phase: \(phase)"
        (text as NSString).draw(at: NSPoint(x: 10, y: 10), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor])
    }
}
