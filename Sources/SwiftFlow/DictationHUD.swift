import SwiftUI
import AppKit

/// Floating pill shown near the bottom of the screen while dictating:
/// live waveform + streaming transcript, then a "polishing" phase.
/// The panel never steals focus and ignores the mouse.
final class DictationHUD {
    enum Phase { case recording, processing }

    final class Model: ObservableObject {
        @Published var levels: [CGFloat] = Model.restingLevels
        @Published var text = ""
        @Published var phase: Phase = .recording
        @Published var handsFree = false
        static let restingLevels = [CGFloat](repeating: 0.06, count: 26)
    }

    let model = Model()
    private var panel: NSPanel?

    func show(handsFree: Bool) {
        model.levels = Model.restingLevels
        model.text = ""
        model.phase = .recording
        model.handsFree = handsFree
        if panel == nil { panel = Self.makePanel(rootView: HUDView(model: model)) }
        position()
        panel?.orderFrontRegardless()
    }

    func pushLevel(_ level: CGFloat) {
        model.levels.removeFirst()
        model.levels.append(max(0.06, level))
    }

    func setHandsFree(_ on: Bool) { model.handsFree = on }

    func setText(_ text: String) { model.text = text }

    func processing() {
        model.phase = .processing
        model.levels = Model.restingLevels
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.minY + 28))
    }

    private static func makePanel(rootView: HUDView) -> NSPanel {
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame.size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI draws its own
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct HUDView: View {
    @ObservedObject var model: DictationHUD.Model
    @State private var pulsing = false

    private var accent: Color { model.handsFree ? .purple : .red }

    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .recording {
                recordingDot
                waveform
                transcript
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Polishing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(width: 460)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(20)  // room for the shadow inside the borderless panel
        .onAppear { pulsing = true }
    }

    private var recordingDot: some View {
        Circle()
            .fill(accent)
            .frame(width: 8, height: 8)
            .opacity(pulsing ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                       value: pulsing)
    }

    private var waveform: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(accent.opacity(0.85))
                    .frame(width: 2.5, height: 4 + level * 22)
            }
        }
        .animation(.linear(duration: 0.08), value: model.levels)
        .frame(height: 28)
    }

    private var transcript: some View {
        Text(model.text.isEmpty ? "Listening…" : model.text)
            .font(.system(size: 12))
            .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.head)  // keep the newest words visible
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
