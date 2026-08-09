import SwiftUI
import Charts

/// Dictation analytics computed straight from the SQLite-backed store.
struct InsightsView: View {
    @ObservedObject var store: TranscriptStore

    private var calendar: Calendar { .current }

    private func words(_ entries: [TranscriptEntry]) -> Int {
        entries.reduce(0) { $0 + $1.displayText.split(separator: " ").count }
    }

    private var todayEntries: [TranscriptEntry] {
        store.entries.filter { calendar.isDateInToday($0.createdAt) }
    }

    private var weekEntries: [TranscriptEntry] {
        guard let weekAgo = calendar.date(byAdding: .day, value: -6,
                                          to: calendar.startOfDay(for: Date())) else { return [] }
        return store.entries.filter { $0.createdAt >= weekAgo }
    }

    private var totalSeconds: Double { store.entries.reduce(0) { $0 + $1.duration } }

    /// Words per minute while actually speaking.
    private var pace: Int {
        guard totalSeconds > 10 else { return 0 }
        return Int((Double(words(store.entries)) / (totalSeconds / 60)).rounded())
    }

    /// Rough minutes saved vs typing the same words at 40 WPM.
    private var minutesSaved: Int {
        let typingMinutes = Double(words(store.entries)) / 40
        return max(0, Int((typingMinutes - totalSeconds / 60).rounded()))
    }

    private struct DayCount: Identifiable {
        let day: Date
        let words: Int
        var id: Date { day }
    }

    private var last14Days: [DayCount] {
        let start = calendar.startOfDay(for: Date())
        let byDay = Dictionary(grouping: store.entries) { calendar.startOfDay(for: $0.createdAt) }
        return (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return DayCount(day: day, words: words(byDay[day] ?? []))
        }.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tileGrid
                chartSection
            }
            .padding(20)
        }
    }

    private var tileGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  spacing: 8) {
            StatTile(value: words(todayEntries).formatted(), label: "Words today",
                     symbol: "sun.max")
            StatTile(value: words(weekEntries).formatted(), label: "Words this week",
                     symbol: "calendar")
            StatTile(value: words(store.entries).formatted(), label: "Words all time",
                     symbol: "textformat")
            StatTile(value: pace > 0 ? "\(pace) wpm" : "—", label: "Speaking pace",
                     symbol: "gauge.with.needle")
            StatTile(value: HistoryView.longDuration(totalSeconds), label: "Speaking time",
                     symbol: "clock")
            StatTile(value: minutesSaved > 0 ? "\(minutesSaved) min" : "—",
                     label: "Saved vs typing", symbol: "hare")
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 14 days")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            Chart(last14Days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Words", day.words)
                )
                .foregroundStyle(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.defaultDigits),
                                   centered: true)
                        .font(.system(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Color(nsColor: .separatorColor).opacity(0.4))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .frame(height: 180)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }
}

// Shared stat tile (also used by the header in earlier designs).
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}
