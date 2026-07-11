import Foundation
import VoiceFlowCore

func runHistoryTests() {
    T.run("history: newest first") {
        let h = HistoryStore(capacity: 3)
        h.add("один")
        h.add("два")
        T.equal(h.entries.map(\.text), ["два", "один"])
    }

    T.run("history: capacity enforced") {
        let h = HistoryStore(capacity: 3)
        for s in ["1", "2", "3", "4", "5"] { h.add(s) }
        T.equal(h.entries.map(\.text), ["5", "4", "3"])
    }
}
