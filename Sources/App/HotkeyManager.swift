import Foundation
import AppKit
import Carbon.HIToolbox

class HotkeyManager {

    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("DLock: failed to create event tap (needs Accessibility permissions)")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            eventTap = nil
            runLoopSource = nil
            isEnabled = false
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            let controlPressed = flags.contains(.maskControl)
            let altPressed = flags.contains(.maskAlternate)
            _ = flags.contains(.maskCommand)
            // Cmd+Ctrl+Alt+D
            if controlPressed && altPressed && keyCode == 2 {
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
                return nil // consume the event
            }
        }
        return Unmanaged.passRetained(event)
    }

    deinit {
        unregister()
    }
}
