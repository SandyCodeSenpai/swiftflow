import Foundation
import CoreGraphics

/// Push-to-talk on the RIGHT OPTION (⌥) key plus a hands-free lock combo
/// (any ⌥ + Space), watched via a CGEvent tap. Requires Accessibility
/// permission. The lock combo is consumed so it never types into the app.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onLockCombo: (() -> Void)?

    private var eventTap: CFMachPort?
    private var pressed = false
    private static let rightOptionKeycode: Int64 = 61
    private static let spaceKeycode: Int64 = 49

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                let consumed = manager.handle(event: event, type: type)
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Returns true when the event was consumed and must not reach other apps.
    private func handle(event: CGEvent, type: CGEventType) -> Bool {
        // macOS disables taps that stall; re-enable so the hotkey never dies.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown {
            guard keycode == Self.spaceKeycode,
                  event.flags.contains(.maskAlternate),
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0
            else { return false }
            DispatchQueue.main.async { self.onLockCombo?() }
            return true
        }

        guard type == .flagsChanged, keycode == Self.rightOptionKeycode else { return false }

        let isDown = event.flags.contains(.maskAlternate)
        if isDown && !pressed {
            pressed = true
            DispatchQueue.main.async { self.onPress?() }
        } else if !isDown && pressed {
            pressed = false
            DispatchQueue.main.async { self.onRelease?() }
        }
        return false
    }
}
