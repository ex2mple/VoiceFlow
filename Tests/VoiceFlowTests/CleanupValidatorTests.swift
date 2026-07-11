import Foundation
import VoiceFlowCore

func runCleanupValidatorTests() {
    T.run("validator: honest cleanup accepted") {
        let orig = "ну короче запиши меня на пятницу нет на субботу к трём"
        let cleaned = "Запиши меня на субботу к трём."
        T.equal(CleanupValidator.validate(original: orig, cleaned: cleaned), cleaned)
    }

    T.run("validator: model answering instead of cleaning is rejected") {
        let orig = "напиши васе что я опоздаю"
        let answer = """
        Привет, Вася! Хочу предупредить, что я сегодня немного задержусь. \
        Прости за неудобства, постараюсь быть как можно скорее. Обнимаю!
        """
        T.equal(CleanupValidator.validate(original: orig, cleaned: answer), nil)
    }

    T.run("validator: empty result rejected") {
        T.equal(CleanupValidator.validate(original: "привет мир", cleaned: "  \n"), nil)
    }

    T.run("validator: <think> block stripped") {
        let got = CleanupValidator.stripArtifacts("<think>хм, надо убрать ну</think>Привет, мир!")
        T.equal(got, "Привет, мир!")
    }

    T.run("validator: surrounding quotes stripped") {
        T.equal(CleanupValidator.stripArtifacts("\"Привет, мир!\""), "Привет, мир!")
        T.equal(CleanupValidator.stripArtifacts("«Привет, мир!»"), "Привет, мир!")
    }

    T.run("validator: code fence stripped") {
        T.equal(CleanupValidator.stripArtifacts("```\nПривет\n```"), "Привет")
    }

    T.run("validator: short phrase gets loose bounds") {
        // "да" → "Да." почти вдвое длиннее — для коротких фраз это норма.
        T.equal(CleanupValidator.validate(original: "да", cleaned: "Да."), "Да.")
    }

    T.run("validator: summarized long dictation is rejected") {
        let orig = String(repeating: "я хочу чтобы эта штука переводила текст в рантайме ", count: 6)
        let summary = "Хочу перевод текста в рантайме."
        T.equal(CleanupValidator.validate(original: orig, cleaned: summary), nil)
    }

    T.run("validator: long dictation lightly trimmed is accepted") {
        let orig = String(repeating: "ну вот я думаю что надо сделать так и никак иначе ", count: 6)
        let cleaned = String(repeating: "Я думаю, что надо сделать так и никак иначе. ", count: 6)
            .trimmingCharacters(in: .whitespaces)
        T.equal(CleanupValidator.validate(original: orig, cleaned: cleaned), cleaned)
    }
}
