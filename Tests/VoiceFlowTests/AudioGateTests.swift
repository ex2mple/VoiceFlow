import Foundation
import VoiceFlowCore

func runAudioGateTests() {
    let sr = 16000.0

    T.run("gate: silence rejected") {
        let silence = [Float](repeating: 0, count: 16000)
        T.expect(!AudioGate.shouldTranscribe(samples: silence, sampleRate: sr), "silence must not pass")
    }

    T.run("gate: too short rejected even if loud") {
        let short = [Float](repeating: 0.5, count: 1000) // ~60 ms
        T.expect(!AudioGate.shouldTranscribe(samples: short, sampleRate: sr), "short burst must not pass")
    }

    T.run("gate: speech-like signal passes") {
        var speech = [Float]()
        for i in 0..<16000 { speech.append(sinf(Float(i) * 0.05) * 0.1) }
        T.expect(AudioGate.shouldTranscribe(samples: speech, sampleRate: sr), "1s tone at 0.1 amp must pass")
    }

    T.run("gate: rms math") {
        T.equal(AudioGate.rms([]), 0)
        let r = AudioGate.rms([Float](repeating: 0.5, count: 100))
        T.expect(abs(r - 0.5) < 0.0001, "rms of constant 0.5 is 0.5, got \(r)")
    }

    T.run("gate: wedged mic = long run of exact zeros") {
        // A live mic always has a noise floor; the stuck-HAL state (the
        // system-wide «микрофон умер» bug) delivers bit-exact zeros.
        let zeros = [Float](repeating: 0, count: 16000)
        T.expect(AudioGate.isDeadInput(samples: zeros, sampleRate: sr),
                 "1s of exact zeros = wedged input")
    }

    T.run("gate: quiet-but-alive mic is not wedged") {
        let faint = [Float](repeating: 1e-6, count: 16000)
        T.expect(!AudioGate.isDeadInput(samples: faint, sampleRate: sr),
                 "noise floor means the mic works")
        var speech = [Float]()
        for i in 0..<16000 { speech.append(sinf(Float(i) * 0.05) * 0.1) }
        T.expect(!AudioGate.isDeadInput(samples: speech, sampleRate: sr), "speech is not wedged")
    }

    T.run("gate: short zero runs are inconclusive") {
        let blip = [Float](repeating: 0, count: 3200) // 0.2s — could be a quick tap
        T.expect(!AudioGate.isDeadInput(samples: blip, sampleRate: sr),
                 "too short to declare the mic dead")
        T.expect(!AudioGate.isDeadInput(samples: [], sampleRate: sr), "empty buffer")
    }
}
