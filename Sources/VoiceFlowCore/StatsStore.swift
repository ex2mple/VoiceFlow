import Foundation

public struct StatsSnapshot: Equatable {
    public let wordsToday: Int
    public let wordsTotal: Int
    public let dictationsTotal: Int
    public let secondsRecorded: Double

    /// Rough «время за клавиатурой, которое не потрачено»: ~1 сек на слово
    /// (разница между печатью ~40 слов/мин и речью ~130 слов/мин).
    public var savedMinutes: Int {
        Int((Double(wordsTotal) * 1.0 / 60).rounded())
    }
}

/// Dictation counters persisted in UserDefaults. Not thread-safe: call from
/// the main queue (the coordinator already lives there).
public final class StatsStore {
    private let d: UserDefaults
    private let keyWordsTotal = "stats.total.words"
    private let keyDictations = "stats.total.dictations"
    private let keySeconds = "stats.total.seconds"
    private let keyTodayDate = "stats.today.date"
    private let keyTodayWords = "stats.today.words"

    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    public func record(text: String, duration: Double, now: Date = Date()) {
        let words = Self.wordCount(text)
        guard words > 0 else { return }
        d.set(d.integer(forKey: keyWordsTotal) + words, forKey: keyWordsTotal)
        d.set(d.integer(forKey: keyDictations) + 1, forKey: keyDictations)
        d.set(d.double(forKey: keySeconds) + duration, forKey: keySeconds)

        let today = Self.dayString(now)
        if d.string(forKey: keyTodayDate) == today {
            d.set(d.integer(forKey: keyTodayWords) + words, forKey: keyTodayWords)
        } else {
            d.set(today, forKey: keyTodayDate)
            d.set(words, forKey: keyTodayWords)
        }
    }

    public func snapshot(now: Date = Date()) -> StatsSnapshot {
        let todayWords = d.string(forKey: keyTodayDate) == Self.dayString(now)
            ? d.integer(forKey: keyTodayWords) : 0
        return StatsSnapshot(
            wordsToday: todayWords,
            wordsTotal: d.integer(forKey: keyWordsTotal),
            dictationsTotal: d.integer(forKey: keyDictations),
            secondsRecorded: d.double(forKey: keySeconds))
    }

    public static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    /// Русская форма: 1 слово, 2 слова, 5 слов.
    public static func wordsForm(_ n: Int) -> String {
        let mod100 = n % 100
        let mod10 = n % 10
        if (11...14).contains(mod100) { return "слов" }
        if mod10 == 1 { return "слово" }
        if (2...4).contains(mod10) { return "слова" }
        return "слов"
    }
}
