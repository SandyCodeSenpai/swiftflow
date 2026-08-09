import SwiftUI
import AppKit

// MARK: - History tab

/// Searchable day-grouped dictation feed with expandable cards and
/// hover actions. Hosted inside MainWindowView.
struct HistoryView: View {
    @ObservedObject var store: TranscriptStore
    @State private var query = ""
    @State private var expandedID: Int64?
    @State private var copiedID: Int64?
    @State private var confirmingClear = false
    @FocusState private var searchFocused: Bool

    private var filtered: [TranscriptEntry] {
        guard !query.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.displayText.localizedCaseInsensitiveContains(query)
                || $0.raw.localizedCaseInsensitiveContains(query)
        }
    }

    private var days: [(Date, [TranscriptEntry])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            if filtered.isEmpty {
                emptyState
            } else {
                feed
            }
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search transcripts", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.6)
                                            : Color(nsColor: .separatorColor).opacity(0.6),
                              lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: searchFocused)
    }

    // MARK: Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(days, id: \.0) { day, dayEntries in
                    Section {
                        ForEach(dayEntries) { entry in
                            TranscriptCard(
                                entry: entry,
                                expanded: expandedID == entry.id,
                                copied: copiedID == entry.id,
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        expandedID = expandedID == entry.id ? nil : entry.id
                                    }
                                },
                                onCopy: { copy(entry.displayText, id: entry.id) },
                                onCopyRaw: { copy(entry.raw, id: entry.id) },
                                onDelete: {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        store.delete(entry.id)
                                    }
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(Self.dayLabel(day))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(0.6)
                            Spacer()
                            Text("\(dayEntries.count)")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .background(Rectangle().fill(.ultraThinMaterial).padding(.horizontal, -20))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: query.isEmpty ? "waveform.and.mic" : "magnifyingglass")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 4) {
                Text(query.isEmpty ? "No transcripts yet" : "No matches")
                    .font(.system(size: 15, weight: .semibold))
                Text(query.isEmpty
                     ? "Your dictations will appear here the moment you speak."
                     : "Nothing matches “\(query)”.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if query.isEmpty {
                HStack(spacing: 5) {
                    Text("Hold")
                    KeyCap("⌥ right option")
                    Text("and talk")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("Stored locally · ~/.swiftflow/history.db")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                confirmingClear = true
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.entries.isEmpty ? Color.secondary.opacity(0.4) : .secondary)
            .disabled(store.entries.isEmpty)
            .confirmationDialog("Delete all \(store.entries.count) transcripts?",
                                isPresented: $confirmingClear) {
                Button("Delete All", role: .destructive) {
                    withAnimation { store.clearAll() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Rectangle().fill(.ultraThinMaterial))
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }

    // MARK: Helpers

    private func copy(_ text: String, id: Int64) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id { copiedID = nil }
        }
    }

    private static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func longDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

// MARK: - Keycap hint

private struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

// MARK: - Transcript card

private struct TranscriptCard: View {
    let entry: TranscriptEntry
    let expanded: Bool
    let copied: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onCopyRaw: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var wasCleaned: Bool {
        if let cleaned = entry.cleaned, !cleaned.isEmpty, cleaned != entry.raw { return true }
        return false
    }

    private var wordCount: Int { entry.displayText.split(separator: " ").count }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            metaRow
            Text(entry.displayText)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .lineLimit(expanded ? nil : 3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if expanded && wasCleaned {
                rawSection
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.95 : 0.7))
                .shadow(color: .black.opacity(hovering ? 0.10 : 0.05),
                        radius: hovering ? 7 : 3, y: hovering ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(hovering ? 0.9 : 0.5),
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            if wasCleaned { Button("Copy Raw Transcript", action: onCopyRaw) }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 7) {
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            if entry.duration >= 1 {
                MetaPill(text: HistoryView.longDuration(entry.duration), symbol: "clock")
            }
            MetaPill(text: "\(wordCount)w", symbol: "textformat")
            if wasCleaned {
                MetaPill(text: "Cleaned", symbol: "sparkles", tinted: true)
            }
            Spacer()
            if hovering || copied {
                HStack(spacing: 10) {
                    Button(action: onCopy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript")
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .transition(.opacity)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
    }

    private var rawSection: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Original transcript")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Text(entry.raw)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct MetaPill: View {
    let text: String
    let symbol: String
    var tinted = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .medium))
            Text(text)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .foregroundStyle(tinted ? Color.accentColor : Color.secondary)
        .background(
            Capsule().fill(tinted ? Color.accentColor.opacity(0.13)
                                  : Color(nsColor: .quaternaryLabelColor).opacity(0.35))
        )
    }
}
