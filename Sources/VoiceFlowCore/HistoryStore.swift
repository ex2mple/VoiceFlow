import Foundation

public struct DictationEntry: Equatable {
    public let text: String
    public let date: Date
    public init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

/// Keeps the last N dictations in memory so a failed paste is never lost.
public final class HistoryStore {
    public private(set) var entries: [DictationEntry] = []
    public let capacity: Int

    public init(capacity: Int = 10) {
        self.capacity = capacity
    }

    public func add(_ text: String, date: Date = Date()) {
        entries.insert(DictationEntry(text: text, date: date), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }
}
