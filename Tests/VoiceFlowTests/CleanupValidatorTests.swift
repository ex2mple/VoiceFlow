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
}
