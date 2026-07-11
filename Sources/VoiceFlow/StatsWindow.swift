import AppKit
import Charts
import SwiftUI
import VoiceFlowCore

/// «Полноценное» окно статистики: плитки с числами + график слов по дням.
final class StatsWindowController {
    private var window: NSWindow?

    func show(stats: StatsStore) {
        let view = StatsView(
            snapshot: stats.snapshot(),
            days: stats.recentDays(14).map {
                DayStat(day: $0.day, words: $0.words)
            })

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "Статистика VoiceFlow"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DayStat: Identifiable {
    let day: Date
    let words: Int
    var id: Date { day }
}

struct StatsView: View {
    let snapshot: StatsSnapshot
    let days: [DayStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                tile("Сегодня", "\(snapshot.wordsToday)",
                     StatsStore.wordsForm(snapshot.wordsToday))
                tile("Всего", "\(snapshot.wordsTotal)",
                     StatsStore.wordsForm(snapshot.wordsTotal))
                tile("Диктовок", "\(snapshot.dictationsTotal)", "")
                tile("Сэкономлено", "≈\(snapshot.savedMinutes)", "мин у клавиатуры")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Слова по дням — последние две недели")
                    .font(.headline)
                Chart(days) { day in
                    BarMark(
                        x: .value("День", day.day, unit: .day),
                        y: .value("Слова", day.words))
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.twoDigits))
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func tile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(unit.isEmpty ? " " : unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
