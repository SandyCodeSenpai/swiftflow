import SwiftUI

/// Edits ~/.swiftflow/config.json in place — no relaunch needed.
struct SettingsView: View {
    let initial: Config
    let onSave: (Config) -> Void

    @State private var deepgramKey: String
    @State private var cerebrasKey: String
    @State private var model: String
    @State private var cleanup: Bool
    @State private var sounds: Bool
    @State private var showDeepgramKey = false
    @State private var showCerebrasKey = false
    @State private var saved = false

    private static let knownModels = ["gpt-oss-120b", "zai-glm-4.7", "gemma-4-31b"]

    private var modelOptions: [String] {
        var options = Self.knownModels
        if !options.contains(model) { options.append(model) }
        return options
    }

    private var dirty: Bool {
        deepgramKey != initial.deepgramApiKey
            || cerebrasKey != initial.cerebrasApiKey
            || model != (initial.cerebrasModel ?? "gpt-oss-120b")
            || cleanup != (initial.cleanupEnabled ?? true)
            || sounds != (initial.soundsEnabled ?? true)
    }

    init(initial: Config, onSave: @escaping (Config) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _deepgramKey = State(initialValue: initial.deepgramApiKey)
        _cerebrasKey = State(initialValue: initial.cerebrasApiKey)
        _model = State(initialValue: initial.cerebrasModel ?? "gpt-oss-120b")
        _cleanup = State(initialValue: initial.cleanupEnabled ?? true)
        _sounds = State(initialValue: initial.soundsEnabled ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Transcription", symbol: "waveform") {
                    keyField("Deepgram API key", text: $deepgramKey, revealed: $showDeepgramKey)
                }
                section("AI Cleanup", symbol: "sparkles") {
                    Toggle(isOn: $cleanup) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Clean up transcripts with AI")
                                .font(.system(size: 12))
                            Text("Removes filler words and fixes self-corrections via Cerebras")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    keyField("Cerebras API key", text: $cerebrasKey, revealed: $showCerebrasKey)
                        .disabled(!cleanup)
                        .opacity(cleanup ? 1 : 0.5)
                    HStack {
                        Text("Model")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $model) {
                            ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    .disabled(!cleanup)
                    .opacity(cleanup ? 1 : 0.5)
                }
                section("General", symbol: "gearshape") {
                    Toggle(isOn: $sounds) {
                        Text("Sound effects")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                saveRow
            }
            .padding(20)
        }
    }

    private var saveRow: some View {
        HStack(spacing: 10) {
            Spacer()
            if saved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Button("Save Changes") {
                var config = initial
                config.deepgramApiKey = deepgramKey.trimmingCharacters(in: .whitespaces)
                config.cerebrasApiKey = cerebrasKey.trimmingCharacters(in: .whitespaces)
                config.cerebrasModel = model
                config.cleanupEnabled = cleanup
                config.soundsEnabled = sounds
                onSave(config)
                withAnimation { saved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { saved = false }
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!dirty && !saved)
        }
    }

    private func section(_ title: String, symbol: String,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func keyField(_ label: String, text: Binding<String>,
                          revealed: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Group {
                    if revealed.wrappedValue {
                        TextField("", text: text)
                    } else {
                        SecureField("", text: text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                Button {
                    revealed.wrappedValue.toggle()
                } label: {
                    Image(systemName: revealed.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
        }
    }
}
