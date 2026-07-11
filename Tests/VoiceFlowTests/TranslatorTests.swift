import Foundation
import VoiceFlowCore

func runTranslatorTests() {
    T.run("translator: english output accepted") {
        let got = TextTranslator.validate(
            original: "передай насте что я приду послезавтра",
            translated: "Tell Nastya I'll come the day after tomorrow.")
        T.equal(got, "Tell Nastya I'll come the day after tomorrow.")
    }

    T.run("translator: russian echo rejected") {
        T.equal(TextTranslator.validate(
            original: "передай насте что я приду",
            translated: "Передай Насте, что я приду."), nil)
    }

    T.run("translator: empty and absurd length rejected") {
        T.equal(TextTranslator.validate(original: "привет", translated: "  "), nil)
        T.equal(TextTranslator.validate(
            original: "привет как дела и вообще всё",
            translated: "Hi"), nil)
    }

    T.run("translator: mixed source ok if output mostly latin") {
        let got = TextTranslator.validate(
            original: "надо сделать rollback и перезапустить deploy",
            translated: "We need to roll back and restart the deploy.")
        T.expect(got != nil, "latin-dominant output passes")
    }

    T.run("gain: quiet signal amplified to target peak") {
        let quiet = [Float](repeating: 0.05, count: 100)
        let boosted = AudioGain.normalized(quiet)
        T.expect(abs(boosted[0] - 0.9) < 0.001, "peak 0.05 → 0.9, got \(boosted[0])")
    }

    T.run("gain: loud signal untouched") {
        let loud: [Float] = [0.1, -0.8, 0.5]
        T.equal(AudioGain.normalized(loud), loud)
    }

    T.run("gain: silence untouched, gain capped") {
        T.equal(AudioGain.normalized([0, 0, 0]), [0, 0, 0])
        let whisper = [Float](repeating: 0.001, count: 10)
        let boosted = AudioGain.normalized(whisper)
        T.expect(abs(boosted[0] - 0.025) < 0.0001, "gain capped at 25×, got \(boosted[0])")
    }
}
