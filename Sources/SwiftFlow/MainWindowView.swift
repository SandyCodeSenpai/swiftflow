import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

final class MainWindowState: ObservableObject {
    enum Tab: String, CaseIterable {
        case history = "History"
        case insights = "Insights"
        case settings = "Settings"
    }
    @Published var tab: Tab = .history
}

/// The app window: frosted background, app mark, and History / Insights /
/// Settings tabs.
struct MainWindowView: View {
    @ObservedObject var store: TranscriptStore
    @ObservedObject var state: MainWindowState
    let currentConfig: () -> Config
    let onSaveConfig: (Config) -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            switch state.tab {
            case .history:
                HistoryView(store: store)
            case .insights:
                InsightsView(store: store)
            case .settings:
                SettingsView(initial: currentConfig(), onSave: onSaveConfig)
                    .id(state.tab)  // re-read config each time the tab is opened
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .background(VisualEffectBackground().ignoresSafeArea())
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("SwiftFlow")
                    .font(.system(size: 16, weight: .semibold))
                Text("Push-to-talk dictation")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $state.tab) {
                ForEach(MainWindowState.Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)
        }
        .padding(.top, 36)   // clears the traffic lights on the transparent title bar
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}
