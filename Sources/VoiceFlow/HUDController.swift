import AppKit

/// Floating capsule above the Dock: live waveform while listening,
/// a travelling wave while Whisper/LLM crunch the audio.
final class HUDController {
    enum Mode {
        case listening
        case processing
    }

    private lazy var panel: NSPanel = makePanel()
    private let waveform = WaveformView()

    func show(_ mode: Mode) {
        waveform.mode = mode == .listening ? .live : .synthetic
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        waveform.mode = .off
        panel.orderOut(nil)
    }

    func pushLevel(_ level: Float) {
        waveform.push(level)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 220, height: 44)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = size.height / 2
        effect.layer?.masksToBounds = true

        waveform.frame = effect.bounds.insetBy(dx: 18, dy: 8)
        waveform.autoresizingMask = [.width, .height]
        effect.addSubview(waveform)
        panel.contentView = effect
        return panel
    }

    /// Bottom-center of the screen the user is looking at, above the Dock.
    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 28))
    }
}

/// Bar-style waveform. Two data sources:
/// - .live: bars fed by real microphone RMS via push(_:)
/// - .synthetic: a travelling sine wave (processing indicator)
final class WaveformView: NSView {
    enum Mode {
        case off
        case live
        case synthetic
    }

    var mode: Mode = .off {
        didSet {
            if mode == .live { levels = Array(repeating: 0, count: Self.barCount) }
            syncTimer()
            needsDisplay = true
        }
    }

    static let barCount = 32
    private var levels: [Float] = Array(repeating: 0, count: barCount)
    private var phase: CGFloat = 0
    private var timer: Timer?

    func push(_ level: Float) {
        guard mode == .live else { return }
        levels.removeFirst()
        // Typical speech RMS is ~0.01–0.15; stretch it to fill the bar height.
        levels.append(min(1, level * 9))
        needsDisplay = true
    }

    private func syncTimer() {
        timer?.invalidate()
        timer = nil
        guard mode == .synthetic else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.25
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard mode != .off else { return }
        let barWidth: CGFloat = 3
        let gap = (bounds.width - CGFloat(Self.barCount) * barWidth) / CGFloat(Self.barCount - 1)
        let midY = bounds.midY

        for i in 0..<Self.barCount {
            let value: CGFloat
            switch mode {
            case .live:
                value = CGFloat(levels[i])
            case .synthetic:
                value = 0.35 + 0.3 * sin(phase + CGFloat(i) * 0.45)
            case .off:
                value = 0
            }
            let height = max(3, value * bounds.height)
            let x = CGFloat(i) * (barWidth + gap)
            let bar = NSBezierPath(
                roundedRect: NSRect(x: x, y: midY - height / 2, width: barWidth, height: height),
                xRadius: barWidth / 2, yRadius: barWidth / 2)
            let alpha: CGFloat = mode == .live ? 0.95 : 0.55
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            bar.fill()
        }
    }
}
