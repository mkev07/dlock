import AppKit

@main struct HotkeyChecks {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }
        let modifiers: [CGEventFlags] = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 2, keyDown: true)!
        for combination in 0..<16 {
            event.flags = modifiers.enumerated().reduce(CGEventFlags()) { flags, item in
                combination & (1 << item.offset) != 0 ? flags.union(item.element) : flags
            }
            check(HotkeyManager.matchesShortcut(event) == (combination == 7), "modifier combination \(combination)")
        }
        event.flags = [.maskCommand, .maskControl, .maskAlternate, .maskAlphaShift]
        check(HotkeyManager.matchesShortcut(event), "Caps Lock does not block shortcut")
        event.setIntegerValueField(.keyboardEventKeycode, value: 3)
        check(!HotkeyManager.matchesShortcut(event), "different key rejected")
        let manager = HotkeyManager.shared
        let forwarded = manager.handleEvent(type: .keyDown, event: event)
        check(forwarded?.takeUnretainedValue() === event, "unrelated event passed through unchanged")
        for eventType in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            check(manager.handleEvent(type: eventType, event: event)?.takeUnretainedValue() === event,
                  "disabled tap notification passed through")
        }
        event.setIntegerValueField(.keyboardEventKeycode, value: 2)
        event.flags = [.maskCommand, .maskControl, .maskAlternate]
        var callbackCount = 0
        manager.onHotkeyPressed = { callbackCount += 1 }
        check(manager.handleEvent(type: .keyDown, event: event) == nil, "shortcut consumed")
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        check(manager.handleEvent(type: .keyDown, event: event) == nil, "repeat consumed")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(callbackCount == 1, "repeat does not reopen controls")
        check(manager.handleEvent(type: .keyUp, event: event)?.takeUnretainedValue() === event, "key up passed through")
        manager.onHotkeyPressed = nil
        exit(failures == 0 ? 0 : 1)
    }
}
