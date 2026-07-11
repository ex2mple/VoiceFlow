import AppKit

/// Floating capsule above the Dock: live transcript + smooth wave while
/// listening, a dimmed travelling wave while Whisper/LLM crunch the audio.
final class HUDController {
    enum Mode {
        case listening
        case processing
    }

    private static let waveOnlyWidth: CGFloat = 230
    private static let transcriptWidth: CGFloat = 460
    private static let waveHeight: CGFloat = 44
    private static let textHeight: CGFloat = 96

    private lazy var panel: NSPanel = makePanel()
    private let wave = WaveView()
    private let transcriptLabel = NSTextField(wrappingLabelWithString: "")
    private var hasTranscript = false

    func show(_ mode: Mode) {
        switch mode {
        case .listening:
            hasTranscript = false
            transcriptLabel.stringValue = ""
            wave.mode = .live
        case .processing:
            wave.mode = .synthetic
        }
        layout()
        panel.orderFrontRegardless()
    }

    func hide() {
        wave.mode = .off
        hasTranscript = false
        transcriptLabel.stringValue = ""
        panel.orderOut(nil)
    }

    func pushLevel(_ level: Float) {
        wave.push(level)
    }

    /// Live partial transcript while the user is still speaking.
    func showTranscript(_ text: String) {
        guard wave.mode != .off, !text.isEmpty else { return }
        transcriptLabel.stringValue = text
        if !hasTranscript {
            hasTranscript = true
            layout()
        }
    }

    // MARK: - Window plumbing

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.waveOnlyWidth, height: Self.waveHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.waveHeight / 2
        effect.layer?.masksToBounds = true

        transcriptLabel.font = .systemFont(ofSize: 13)
        transcriptLabel.textColor = .labelColor
        transcriptLabel.alignment = .center
        transcriptLabel.maximumNumberOfLines = 5
        // The tail of the transcript is the fresh part — clip the beginning.
        transcriptLabel.lineBreakMode = .byTruncatingHead

        effect.addSubview(transcriptLabel)
        effect.addSubview(wave)
        panel.contentView = effect
        return panel
    }

    /// Bottom-center of the screen, above the Dock; grows upward for the
    /// transcript so the wave stays put.
    private func layout() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = hasTranscript ? Self.transcriptWidth : Self.waveOnlyWidth
        let height = hasTranscript ? Self.waveHeight + Self.textHeight : Self.waveHeight
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - width / 2, y: frame.minY + 28)
        panel.setFrame(
            NSRect(origin: origin, size: NSSize(width: width, height: height)),
            display: true)

        guard let effect = panel.contentView else { return }
        effect.layer?.cornerRadius = hasTranscript ? 18 : Self.waveHeight / 2
        // The wave keeps its compact width even when the capsule widens for
        // the transcript — only the window stretches, not the bars.
        let waveWidth = Self.waveOnlyWidth - 36
        wave.frame = NSRect(
            x: (width - waveWidth) / 2, y: 8, width: waveWidth, height: Self.waveHeight - 16)
        transcriptLabel.frame = NSRect(
            x: 16, y: Self.waveHeight - 2, width: width - 32, height: Self.textHeight - 8)
        transcriptLabel.isHidden = !hasTranscript
    }
}

/// Bar-style level meter (no timeline): all bars dance with the CURRENT
/// microphone level. A flattened envelope keeps even the edge bars alive,
/// per-bar random jitter makes the picture organic. Tinted with the user's
/// macOS accent color.
/// - .live: bars driven by the mic
/// - .synthetic: dimmed travelling wave (processing indicator)
final class WaveView: NSView {
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

    static let barCount = 22
    private var heights: [CGFloat] = Array(repeating: 0, count: barCount)
    private var currentLevel: CGFloat = 0
    private var phase: CGFloat = 0
    private var timer: Timer?

    /// Bell envelope как в первой версии: 1.0 в центре, спад к краям.
    private static let envelope: [CGFloat] = (0..<barCount).map { i in
        let x = (CGFloat(i) - CGFloat(barCount - 1) / 2) / (CGFloat(barCount) / 3.2)
        return 0.15 + 0.85 * exp(-x * x)
    }

    func push(_ level: Float) {
        guard mode == .live else { return }
        // dB scale, not linear: speech RMS lives around 0.01–0.1, which is
        // invisible on a linear meter. Map -55 dB (room noise) … -15 dB
        // (loud speech) onto 0…1, then apply the user's sensitivity.
        let db = 20 * log10(max(CGFloat(level), 0.00005))
        let norm = min(1, max(0, (db + 55) / 40))
        let scaled = min(1, norm * CGFloat(AppSettings.waveSensitivity))
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
                // Pure random jitter per bar — no phase term, no timeline feel.
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
                value = (0.35 + 0.3 * sin(phase + CGFloat(i) * 0.45)) * Self.envelope[i]
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
