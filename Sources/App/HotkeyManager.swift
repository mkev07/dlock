import Foundation
import AppKit
import Carbon.HIToolbox

class HotkeyManager {

    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventRunLoop: CFRunLoop?
    private var isEnabled = false

    var onHotkeyPressed: (() -> Void)?

    private init() {}

    func register() {
        guard !isEnabled else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("DLock: failed to create event tap (needs Accessibility permissions)")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        eventTap = tap
        runLoopSource = source
        eventRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(eventRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource, let runLoop = eventRunLoop {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
            runLoopSource = nil
            eventRunLoop = nil
            isEnabled = false
        }
    }

    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isEnabled, let tap = eventTap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown && Self.matchesShortcut(event) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    static func matchesShortcut(_ event: CGEvent) -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let required: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        return event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_D)
            && event.flags.intersection(modifiers) == required
    }

    deinit {
        unregister()
    }
}
