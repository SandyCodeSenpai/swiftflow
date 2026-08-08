import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }

    private var statusItem: NSStatusItem!
    private var cleanupMenuItem: NSMenuItem!
    private var soundsMenuItem: NSMenuItem!
    private let hotkey = HotkeyManager()
    private let audio = AudioCapture()
    private var deepgram: DeepgramClient?
    private var config: Config!
    private var cleanupEnabled = true
    private var soundsEnabled = true
    private var state: State = .idle { didSet { updateStatusIcon() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let loaded = Config.load() else {
            fatalAlert("Missing config",
                       "Create \(Config.path.path) with deepgram_api_key and cerebras_api_key.")
            return
        }
        config = loaded
        cleanupEnabled = loaded.cleanupEnabled ?? true
        soundsEnabled = loaded.soundsEnabled ?? true
        if config.deepgramApiKey.isEmpty || config.deepgramApiKey.hasPrefix("PASTE_") {
            fatalAlert("Deepgram key missing",
                       "Add your Deepgram API key to \(Config.path.path) and relaunch.")
            return
        }

        Log.write("launched; accessibility trusted=\(AXIsProcessTrusted())")
        setupStatusItem()
        requestPermissions()

        hotkey.onPress = { [weak self] in self?.startDictation() }
        hotkey.onRelease = { [weak self] in self?.stopDictation() }
        startHotkey(firstAttempt: true)
    }

    /// Retries until Accessibility is granted, so the user never has to relaunch.
    private func startHotkey(firstAttempt: Bool) {
        if hotkey.start() {
            Log.write("event tap started — hotkey active")
            return
        }
        Log.write("event tap failed (Accessibility not granted); retrying in 3s")
        if firstAttempt {
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.startHotkey(firstAttempt: false)
        }
    }

    // MARK: - Dictation flow

    private func startDictation() {
        guard state == .idle else { return }
        state = .recording
        Log.write("hotkey pressed — recording")
        playSound("Pop")

        let client = DeepgramClient(apiKey: config.deepgramApiKey)
        deepgram = client
        client.onFinalTranscript = { [weak self] transcript in
            self?.handleTranscript(transcript)
        }
        client.connect()

        audio.onAudio = { [weak client] chunk in client?.send(chunk) }
        do {
            try audio.start()
        } catch {
            Log.write("audio start FAILED: \(error.localizedDescription)")
            state = .idle
            deepgram = nil
        }
    }

    private func stopDictation() {
        guard state == .recording else { return }
        state = .processing
        Log.write("hotkey released — finishing")
        audio.stop()
        deepgram?.finish()
    }

    private func handleTranscript(_ transcript: String) {
        deepgram = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.write("transcript received (\(text.count) chars)")
        guard !text.isEmpty else {
            playSound("Basso")  // nothing captured — let the user know
            state = .idle
            return
        }
        if cleanupEnabled, !config.cerebrasApiKey.isEmpty {
            let cerebras = CerebrasClient(apiKey: config.cerebrasApiKey,
                                          model: config.cerebrasModel ?? "llama-3.3-70b")
            cerebras.cleanup(text) { [weak self] cleaned in
                TextInjector.inject(cleaned)
                self?.playSound("Tink")
                self?.state = .idle
            }
        } else {
            TextInjector.inject(text)
            playSound("Tink")
            state = .idle
        }
    }

    private func playSound(_ name: String) {
        guard soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "Hold Right ⌥ to dictate", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        cleanupMenuItem = NSMenuItem(title: "AI Cleanup (Cerebras)",
                                     action: #selector(toggleCleanup), keyEquivalent: "")
        cleanupMenuItem.target = self
        cleanupMenuItem.state = cleanupEnabled ? .on : .off
        menu.addItem(cleanupMenuItem)
        soundsMenuItem = NSMenuItem(title: "Sound Effects",
                                    action: #selector(toggleSounds), keyEquivalent: "")
        soundsMenuItem.target = self
        soundsMenuItem.state = soundsEnabled ? .on : .off
        menu.addItem(soundsMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SwiftFlow", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let description: String
        let tint: NSColor?
        switch state {
        case .idle:
            symbol = "mic"; description = "SwiftFlow idle"; tint = nil
        case .recording:
            symbol = "mic.fill"; description = "SwiftFlow recording"; tint = .systemRed
        case .processing:
            symbol = "waveform"; description = "SwiftFlow processing"; tint = .systemOrange
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        image?.isTemplate = true
        button.image = image
        button.title = ""
        button.contentTintColor = tint
    }

    @objc private func toggleCleanup() {
        cleanupEnabled.toggle()
        cleanupMenuItem.state = cleanupEnabled ? .on : .off
    }

    @objc private func toggleSounds() {
        soundsEnabled.toggle()
        soundsMenuItem.state = soundsEnabled ? .on : .off
    }

    // MARK: - Permissions

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func fatalAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}
