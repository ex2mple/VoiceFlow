import Foundation
import VoiceFlowCore

func runSanitizerTests() {
    T.run("sanitizer: normal text passes through") {
        T.equal(TranscriptSanitizer.clean("Привет, как дела?"), "Привет, как дела?")
    }

    T.run("sanitizer: hallucination-only input becomes empty") {
        T.equal(TranscriptSanitizer.clean("Субтитры сделал DimaTorzok"), "")
        T.equal(TranscriptSanitizer.clean("Продолжение следует..."), "")
        T.equal(TranscriptSanitizer.clean("Thanks for watching!"), "")
        T.equal(TranscriptSanitizer.clean("Субтитры сделал DimaTorzok. Спасибо за просмотр."), "")
    }

    T.run("sanitizer: hallucination tail is dropped, речь остаётся") {
        let got = TranscriptSanitizer.clean("Запиши меня на пятницу. Субтитры сделал DimaTorzok.")
        T.equal(got, "Запиши меня на пятницу.")
    }

    T.run("sanitizer: non-speech markers stripped") {
        T.equal(TranscriptSanitizer.clean("[BLANK_AUDIO]"), "")
        T.equal(TranscriptSanitizer.clean("(music)"), "")
        T.equal(TranscriptSanitizer.clean("Привет [шум] мир"), "Привет мир")
    }

    T.run("sanitizer: mixed ru/en preserved") {
        let s = "Задеплой на прод через CI, и проверь logs."
        T.equal(TranscriptSanitizer.clean(s), s)
    }

    T.run("sanitizer: whitespace collapsed") {
        T.equal(TranscriptSanitizer.clean("  Привет   мир  \n"), "Привет мир")
    }
}
