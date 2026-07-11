import AppKit

/// Floating capsule above the Dock: live transcript + smooth wave while
/// listening, a dimmed travelling wave while Whisper/LLM crunch the audio.
final class HUDController {
    enum Mode {
        case listening
        case processing
    }

    private static let width: CGFloat = 340
    private static let waveHeight: CGFloat = 44
    private static let textHeight: CGFloat = 46

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
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.waveHeight),
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
        transcriptLabel.maximumNumberOfLines = 2
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
        let height = hasTranscript ? Self.waveHeight + Self.textHeight : Self.waveHeight
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - Self.width / 2, y: frame.minY + 28)
        panel.setFrame(
            NSRect(origin: origin, size: NSSize(width: Self.width, height: height)),
            display: true)

        guard let effect = panel.contentView else { return }
        effect.layer?.cornerRadius = hasTranscript ? 18 : Self.waveHeight / 2
        wave.frame = NSRect(x: 18, y: 8, width: Self.width - 36, height: Self.waveHeight - 16)
        transcriptLabel.frame = NSRect(
            x: 16, y: Self.waveHeight - 2, width: Self.width - 32, height: Self.textHeight - 8)
        transcriptLabel.isHidden = !hasTranscript
    }
}

/// Smooth symmetric wave (no timeline): a filled curve that swells with the
/// CURRENT voice level. Two data sources:
/// - .live: control points eased toward level × bell envelope
/// - .synthetic: a dimmed travelling wave (processing indicator)
final class WaveView: NSView {
    enum Mode {
        case off
        case live
        case synthetic
    }

    var mode: Mode = .off {
        didSet {
            points = Array(repeating: 0, count: Self.pointCount)
            currentLevel = 0
            syncTimer()
            needsDisplay = true
        }
    }

    static let pointCount = 12
    private var points: [CGFloat] = Array(repeating: 0, count: pointCount)
    private var currentLevel: CGFloat = 0
    private var phase: CGFloat = 0
    private var timer: Timer?

    func push(_ level: Float) {
        guard mode == .live else { return }
        // dB scale, not linear: speech RMS lives around 0.01–0.1, which is
        // invisible on a linear meter. Map -55 dB (room noise) … -15 dB
        // (loud speech) onto 0…1, then apply the user's sensitivity.
        let db = 20 * log10(max(CGFloat(level), 0.00005))
        let norm = min(1, max(0, (db + 55) / 40))
        let scaled = min(1, norm * CGFloat(AppSettings.waveSensitivity))
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
        phase += 0.4
        switch mode {
        case .live:
            for i in 0..<Self.pointCount {
                let x = (CGFloat(i) - CGFloat(Self.pointCount - 1) / 2) / (CGFloat(Self.pointCount) / 2.6)
                let envelope = exp(-x * x)
                let ripple = 0.5 + 0.5 * sin(phase + CGFloat(i) * 1.3)
                let target = currentLevel * envelope * ripple
                points[i] += (target - points[i]) * 0.35
            }
            currentLevel *= 0.9
        case .synthetic:
            for i in 0..<Self.pointCount {
                let x = (CGFloat(i) - CGFloat(Self.pointCount - 1) / 2) / (CGFloat(Self.pointCount) / 2.6)
                let envelope = exp(-x * x)
                points[i] = (0.35 + 0.3 * sin(phase * 0.6 + CGFloat(i) * 0.9)) * envelope
            }
        case .off:
            return
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard mode != .off else { return }
        let mid = bounds.midY
        let step = bounds.width / CGFloat(Self.pointCount - 1)
        let alpha: CGFloat = mode == .live ? 0.85 : 0.5

        // Filled symmetric lobe above and below the midline.
        for direction: CGFloat in [1, -1] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: mid))
            for i in 0..<(Self.pointCount - 1) {
                let y1 = mid - direction * max(1.5, points[i] * bounds.height * 0.48)
                let y2 = mid - direction * max(1.5, points[i + 1] * bounds.height * 0.48)
                let midX = CGFloat(i) * step + step / 2
                path.curve(
                    to: NSPoint(x: CGFloat(i + 1) * step, y: (y1 + y2) / 2),
                    controlPoint1: NSPoint(x: midX, y: y1),
                    controlPoint2: NSPoint(x: midX, y: (y1 + y2) / 2))
            }
            path.line(to: NSPoint(x: bounds.width, y: mid))
            path.close()
            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            path.fill()
        }
    }
}
