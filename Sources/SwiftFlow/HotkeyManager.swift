import Foundation
import CoreGraphics

/// Push-to-talk on the RIGHT OPTION (⌥) key, watched via a listen-only
/// CGEvent tap on flagsChanged events. Requires Accessibility permission.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var pressed = false
    private static let rightOptionKeycode: Int64 = 61

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handle(event: event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(event: CGEvent, type: CGEventType) {
        // macOS disables taps that stall; re-enable so the hotkey never dies.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged,
              event.getIntegerValueField(.keyboardEventKeycode) == Self.rightOptionKeycode
        else { return }

        let isDown = event.flags.contains(.maskAlternate)
        if isDown && !pressed {
            pressed = true
            DispatchQueue.main.async { self.onPress?() }
        } else if !isDown && pressed {
            pressed = false
            DispatchQueue.main.async { self.onRelease?() }
        }
    }
}
