import Foundation
import VoiceFlowCore

func runDictionaryTests() {
    T.run("dictionary: parse skips comments and blanks") {
        let text = """
        # комментарий
        WordStash

          задеплоить
        # ещё
        Браудэ
        """
        T.equal(UserDictionary.parse(text), ["WordStash", "задеплоить", "Браудэ"])
    }

    T.run("dictionary: empty input → no prompts") {
        T.equal(UserDictionary.whisperPrompt([]), nil)
        T.equal(UserDictionary.cleanupHint([]), nil)
    }

    T.run("dictionary: prompts contain the words") {
        let p = UserDictionary.whisperPrompt(["WordStash", "Браудэ"])!
        T.expect(p.contains("WordStash") && p.contains("Браудэ"), "words in whisper prompt")
        let h = UserDictionary.cleanupHint(["WordStash"])!
        T.expect(h.contains("WordStash"), "word in cleanup hint")
    }

    T.run("dictionary: vocabulary lands in cleanup system message") {
        let msgs = TextCleaner.messages(for: "привет", vocabulary: ["WordStash"])
        let system = msgs.first?["content"] ?? ""
        T.expect(system.contains("WordStash"), "system prompt mentions dictionary word")
    }

    T.run("stats: recentDays chronological with zeros") {
        let suite = "voiceflow-tests-days"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s = StatsStore(defaults: d)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        s.record(text: "раз два", duration: 1, now: now)
        s.record(text: "три", duration: 1, now: now.addingTimeInterval(-86_400 * 2))
        let days = s.recentDays(3, now: now)
        T.equal(days.count, 3)
        T.equal(days.map(\.words), [1, 0, 2])
    }
}
