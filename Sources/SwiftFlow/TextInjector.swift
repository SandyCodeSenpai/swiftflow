import AppKit
import CoreGraphics

/// Injects text into whatever app has focus: save clipboard → put text on
/// it → synthesize Cmd+V → restore clipboard. Needs Accessibility permission.
enum TextInjector {
    private static let vKeycode: CGKeyCode = 9

    static func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay so the pasteboard write settles before the paste lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)

            // Restore the user's clipboard after the target app has pasted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let saved {
                    pasteboard.clearContents()
                    pasteboard.setString(saved, forType: .string)
                }
            }
        }
    }
}
