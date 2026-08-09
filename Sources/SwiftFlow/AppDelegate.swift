import AppKit
import AVFoundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, recording, processing }

    private var statusItem: NSStatusItem!
    private var cleanupMenuItem: NSMenuItem!
    private var soundsMenuItem: NSMenuItem!
    private var handsFreeMenuItem: NSMenuItem!
    private let hotkey = HotkeyManager()
    private let audio = AudioCapture()
    private var deepgram: DeepgramClient?
    private var config: Config!
    private var cleanupEnabled = true
    private var soundsEnabled = true
    private var sessionID = 0
    private var handsFreeLocked = false
    private var lastHandsFreeUnlock = Date.distantPast
    private var recordingStartedAt: Date?
    private let hud = DictationHUD()
    private let windowState = MainWindowState()
    private var durations: [Int: Double] = [:]
    private var historyWindow: NSWindow?
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
        audio.warmUp()
        audio.onLevel = { [weak self] level in self?.hud.pushLevel(level) }

        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] in self?.hotkeyReleased() }
        hotkey.onLockCombo = { [weak self] in self?.lockComboPressed() }
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

    // MARK: - Hotkey handling

    /// Right ⌥ down: start push-to-talk — or, if hands-free is locked, stop it.
    private func hotkeyPressed() {
        if handsFreeLocked {
            setHandsFree(false)
        } else {
            startDictation()
        }
    }

    /// Right ⌥ up: stop push-to-talk unless hands-free locked it on.
    private func hotkeyReleased() {
        guard !handsFreeLocked else { return }
        stopDictation()
    }

    /// ⌥+Space: toggle hands-free lock. When the combo uses the right ⌥,
    /// the ⌥-down has already fired hotkeyPressed — if that just unlocked,
    /// swallow this Space so the same keystroke doesn't re-lock.
    private func lockComboPressed() {
        if !handsFreeLocked, Date().timeIntervalSince(lastHandsFreeUnlock) < 0.8 { return }
        setHandsFree(!handsFreeLocked)
    }

    private func setHandsFree(_ on: Bool) {
        if on {
            guard !handsFreeLocked else { return }
            if state != .recording { startDictation() }
            handsFreeLocked = state == .recording  // lock only if recording actually started
            if handsFreeLocked { Log.write("hands-free lock ON") }
        } else {
            guard handsFreeLocked else { return }
            handsFreeLocked = false
            lastHandsFreeUnlock = Date()
            Log.write("hands-free lock OFF")
            stopDictation()
        }
        updateHandsFreeMenuItem()
    }

    @objc private func toggleHandsFreeFromMenu() {
        setHandsFree(!handsFreeLocked)
    }

    private func updateHandsFreeMenuItem() {
        handsFreeMenuItem?.title = handsFreeLocked ? "Stop Hands-Free Dictation"
                                                   : "Start Hands-Free Dictation"
        handsFreeMenuItem?.state = handsFreeLocked ? .on : .off
        hud.setHandsFree(handsFreeLocked)
        updateStatusIcon()
    }

    // MARK: - Dictation flow

    private func startDictation() {
        // A previous dictation may still be flushing/cleaning up; don't make the
        // user wait for it — start a fresh session and let the old one finish
        // in the background (its text still gets injected when it arrives).
        guard state != .recording else { return }
        if state == .processing {
            Log.write("hotkey pressed while previous dictation still processing")
        }
        sessionID += 1
        let id = sessionID
        let startedAt = Date()
        recordingStartedAt = startedAt
        state = .recording
        Log.write("hotkey pressed — recording")
        playSound("Pop")
        hud.show(handsFree: handsFreeLocked)

        let client = DeepgramClient(apiKey: config.deepgramApiKey)
        deepgram = client
        client.onFinalTranscript = { [weak self] transcript in
            self?.handleTranscript(transcript, session: id, startedAt: startedAt)
        }
        client.onLiveTranscript = { [weak self] live in
            guard let self, id == self.sessionID else { return }
            self.hud.setText(live)
        }
        client.connect()

        audio.onAudio = { [weak client] chunk in client?.send(chunk) }
        do {
            try audio.start()
        } catch {
            Log.write("audio start FAILED: \(error.localizedDescription)")
            state = .idle
            deepgram = nil
            hud.hide()
        }
    }

    private func stopDictation() {
        guard state == .recording else { return }
        state = .processing
        if let startedAt = recordingStartedAt {
            durations[sessionID] = Date().timeIntervalSince(startedAt)
        }
        Log.write("hotkey released — finishing")
        hud.processing()
        audio.stop()
        deepgram?.finish()
    }

    private func handleTranscript(_ transcript: String, session id: Int, startedAt: Date) {
        // A newer dictation may have started while this one was flushing;
        // stale sessions still inject their text but must not touch state.
        let isCurrent = id == sessionID
        if isCurrent { deepgram = nil }
        let duration = durations.removeValue(forKey: id) ?? 0
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.write("transcript received (\(text.count) chars)")
        guard !text.isEmpty else {
            if isCurrent {
                playSound("Basso")  // nothing captured — let the user know
                state = .idle
                hud.hide()
            }
            return
        }
        if cleanupEnabled, !config.cerebrasApiKey.isEmpty {
            let cerebras = CerebrasClient(apiKey: config.cerebrasApiKey,
                                          model: config.cerebrasModel ?? "gpt-oss-120b")
            cerebras.cleanup(text) { [weak self] cleaned in
                guard let self else { return }
                TextInjector.inject(cleaned)
                TranscriptStore.shared.save(raw: text, cleaned: cleaned,
                                            duration: duration, at: startedAt)
                if id == self.sessionID {
                    self.playSound("Tink")
                    self.state = .idle
                    self.hud.hide()
                }
            }
        } else {
            TextInjector.inject(text)
            TranscriptStore.shared.save(raw: text, cleaned: nil,
                                        duration: duration, at: startedAt)
            if isCurrent {
                playSound("Tink")
                state = .idle
                hud.hide()
            }
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
        menu.addItem(withTitle: "⌥ Space locks hands-free", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        handsFreeMenuItem = NSMenuItem(title: "Start Hands-Free Dictation",
                                       action: #selector(toggleHandsFreeFromMenu),
                                       keyEquivalent: " ")
        handsFreeMenuItem.keyEquivalentModifierMask = [.option]
        handsFreeMenuItem.target = self
        menu.addItem(handsFreeMenuItem)
        let historyItem = NSMenuItem(title: "Transcript History…",
                                     action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)
        let insightsItem = NSMenuItem(title: "Insights…",
                                      action: #selector(openInsights), keyEquivalent: "i")
        insightsItem.target = self
        menu.addItem(insightsItem)
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
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
            symbol = "mic.fill"
            description = handsFreeLocked ? "SwiftFlow recording (hands-free)"
                                          : "SwiftFlow recording"
            tint = handsFreeLocked ? .systemPurple : .systemRed
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

    @objc private func openHistory() { openWindow(tab: .history) }
    @objc private func openInsights() { openWindow(tab: .insights) }
    @objc private func openSettings() { openWindow(tab: .settings) }

    private func openWindow(tab: MainWindowState.Tab) {
        windowState.tab = tab
        if historyWindow == nil {
            let root = MainWindowView(
                store: .shared,
                state: windowState,
                currentConfig: { [weak self] in
                    self?.config ?? Config(deepgramApiKey: "", cerebrasApiKey: "",
                                           cerebrasModel: nil, cleanupEnabled: nil,
                                           soundsEnabled: nil)
                },
                onSaveConfig: { [weak self] in self?.applySettings($0) }
            )
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "SwiftFlow"
            window.setContentSize(NSSize(width: 560, height: 680))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable,
                                .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 480, height: 520)
            window.center()
            historyWindow = window
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySettings(_ new: Config) {
        config = new
        cleanupEnabled = new.cleanupEnabled ?? true
        soundsEnabled = new.soundsEnabled ?? true
        cleanupMenuItem.state = cleanupEnabled ? .on : .off
        soundsMenuItem.state = soundsEnabled ? .on : .off
        new.save()
        Log.write("settings saved (model \(new.cerebrasModel ?? "default"))")
    }

    @objc private func toggleCleanup() {
        cleanupEnabled.toggle()
        cleanupMenuItem.state = cleanupEnabled ? .on : .off
        config.cleanupEnabled = cleanupEnabled
        config.save()
    }

    @objc private func toggleSounds() {
        soundsEnabled.toggle()
        soundsMenuItem.state = soundsEnabled ? .on : .off
        config.soundsEnabled = soundsEnabled
        config.save()
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
