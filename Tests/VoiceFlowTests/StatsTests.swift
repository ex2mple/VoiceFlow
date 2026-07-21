import Foundation
import VoiceFlowCore

func runStatsTests() {
    func makeStore() -> StatsStore {
        let suite = "voiceflow-tests"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return StatsStore(defaults: d)
    }
    let day1 = Date(timeIntervalSince1970: 1_800_000_000)
    let day2 = day1.addingTimeInterval(86_400)

    T.run("stats: word count ignores bare punctuation") {
        T.equal(StatsStore.wordCount("Привет, как дела?"), 3)
        T.equal(StatsStore.wordCount("  —  "), 0)
        T.equal(StatsStore.wordCount("push the fix в прод"), 5)
    }

    T.run("stats: totals accumulate") {
        let s = makeStore()
        s.record(text: "раз два три", duration: 2.5, now: day1)
        s.record(text: "четыре пять", duration: 1.5, now: day1)
        let snap = s.snapshot(now: day1)
        T.equal(snap.wordsTotal, 5)
        T.equal(snap.wordsToday, 5)
        T.equal(snap.dictationsTotal, 2)
        T.expect(abs(snap.secondsRecorded - 4.0) < 0.001, "seconds sum")
    }

    T.run("stats: today resets on a new day, totals stay") {
        let s = makeStore()
        s.record(text: "раз два три", duration: 2, now: day1)
        s.record(text: "четыре", duration: 1, now: day2)
        let snap = s.snapshot(now: day2)
        T.equal(snap.wordsToday, 1)
        T.equal(snap.wordsTotal, 4)
    }

    T.run("stats: empty dictation is not counted") {
        let s = makeStore()
        s.record(text: "  ", duration: 1, now: day1)
        T.equal(s.snapshot(now: day1).dictationsTotal, 0)
    }

    T.run("stats: экономия времени зависит от скорости печати") {
        // 1000 слов, 5 минут диктовки. Печать при 40 wpm заняла бы 25 мин
        // (сэкономлено 20), при 100 wpm — 10 мин (сэкономлено 5).
        let snap = StatsSnapshot(
            wordsToday: 0, wordsTotal: 1000, dictationsTotal: 1, secondsRecorded: 300)
        T.equal(snap.savedMinutes(typingWPM: 40), 20)
        T.equal(snap.savedMinutes(typingWPM: 100), 5)
    }

    T.run("stats: экономия не бывает отрицательной") {
        // Печатает быстрее, чем диктовал — сэкономлено 0, а не минус.
        let snap = StatsSnapshot(
            wordsToday: 0, wordsTotal: 100, dictationsTotal: 1, secondsRecorded: 600)
        T.equal(snap.savedMinutes(typingWPM: 100), 0)
        T.equal(snap.savedMinutes(typingWPM: 0), 0)
    }

    T.run("stats: русские формы слова") {
        T.equal(StatsStore.wordsForm(1), "слово")
        T.equal(StatsStore.wordsForm(3), "слова")
        T.equal(StatsStore.wordsForm(5), "слов")
        T.equal(StatsStore.wordsForm(11), "слов")
        T.equal(StatsStore.wordsForm(21), "слово")
        T.equal(StatsStore.wordsForm(112), "слов")
    }
}
