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

/// Bar-style level meter (no timeline). Two data sources:
/// - .live: all bars dance with the CURRENT microphone level — a bell-shaped
///   envelope keeps the middle tall and the edges short, per-bar jitter makes
///   it feel alive (Siri style).
/// - .synthetic: a travelling sine wave (processing indicator)
final class WaveformView: NSView {
    enum Mode {
        case off
        case live
        case synthetic
    }

    var mode: Mode = .off {
        didSet {
            heights = Array(repeating: 0, count: Self.barCount)
            currentLevel = 0
            syncTimer()
            needsDisplay = true
        }
    }

    static let barCount = 32
    private var heights: [CGFloat] = Array(repeating: 0, count: barCount)
    private var currentLevel: CGFloat = 0
    private var phase: CGFloat = 0
    private var timer: Timer?

    /// Bell envelope: 1.0 in the middle, ~0.15 at the edges.
    private static let envelope: [CGFloat] = (0..<barCount).map { i in
        let x = (CGFloat(i) - CGFloat(barCount - 1) / 2) / (CGFloat(barCount) / 3.2)
        return 0.15 + 0.85 * exp(-x * x)
    }

    func push(_ level: Float) {
        guard mode == .live else { return }
        // Typical speech RMS is ~0.01–0.15; stretch it to fill the bar height.
        let scaled = min(1, CGFloat(level) * 9)
        // Fast attack, slow release: peaks land instantly, silence drains softly.
        currentLevel = max(scaled, currentLevel)
    }

    private func syncTimer() {
        timer?.invalidate()
        timer = nil
        guard mode != .off else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        switch mode {
        case .live:
            for i in 0..<Self.barCount {
                let jitter = CGFloat.random(in: 0.5...1.0)
                let target = currentLevel * Self.envelope[i] * jitter
                heights[i] += (target - heights[i]) * 0.45
            }
            currentLevel *= 0.88
        case .synthetic:
            phase += 0.25
        case .off:
            return
        }
        needsDisplay = true
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
                value = heights[i]
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
