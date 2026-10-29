import AppKit

final class DockController {

    static let shared = DockController()

    enum ChangeResult: Equatable {
        case applied
        /// The preference could not be written or read back; the previous
        /// value was restored and the Dock was left untouched.
        case notSaved
        /// The preference is saved, but the Dock did not relaunch to pick it up.
        case savedWithoutRestart
    }

    private let domain = "com.apple.dock" as CFString
    private let orientationKey = "orientation" as CFString
    private let autohideKey = "autohide" as CFString
    private let sizeLockKey = "size-immutable" as CFString

    private init() {}

    @discardableResult
    func restartDock() -> Bool {
        let previousPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                print("Dlock: Dock restart exited with status \(task.terminationStatus)")
                return false
            }
        } catch {
            print("Dlock: failed to restart Dock: \(error)")
            return false
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let currentPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .first?.processIdentifier
            if let currentPID, currentPID != previousPID { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first != nil
    }

    // MARK: - Orientation

    /// Saves the orientation, verifies it, and relaunches the Dock so it takes
    /// effect. If verification fails the previous value is restored, so the
    /// stored preference never disagrees with what the Dock shows.
    func changeOrientation(to orientation: DockOrientation) -> ChangeResult {
        let previous = readValue(orientationKey)
        guard setOrientation(orientation) else {
            writeValue(orientationKey, previous)
            return .notSaved
        }
        return restartDock() ? .applied : .savedWithoutRestart
    }

    @discardableResult
    private func setOrientation(_ orientation: DockOrientation) -> Bool {
        guard writeValue(orientationKey, orientation.rawValue as CFString) else { return false }
        return readOrientation() == orientation
    }

    /// Returns nil only when the stored value is not a known orientation. An
    /// absent key means the Dock is using its built-in default (bottom).
    func readOrientation() -> DockOrientation? {
        guard let value = readValue(orientationKey) else { return .bottom }
        return (value as? String).flatMap(DockOrientation.init(rawValue:))
    }

    func getOrientation() -> DockOrientation {
        readOrientation() ?? .bottom
    }

    // MARK: - Auto-hide

    func changeAutohide(to enabled: Bool) -> ChangeResult {
        guard let current = readAutohide() else { return .notSaved }
        if current == enabled { return .applied }
        // macOS's Dock shortcut updates the live Dock without restarting it
        // (a restart discards the display selected by the user).
        guard AccessibilityPermission.isGranted(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 2, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 2, keyDown: false) else { return .notSaved }
        down.flags = [.maskCommand, .maskAlternate]
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if readAutohide() == enabled { return .applied }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return .notSaved
    }

    @discardableResult
    private func setAutohide(_ enabled: Bool) -> Bool {
        guard writeValue(autohideKey, enabled ? kCFBooleanTrue : kCFBooleanFalse) else { return false }
        return readAutohide() == enabled
    }

    /// Returns nil only when the stored value is not a boolean. An absent key
    /// means auto-hide is off.
    func readAutohide() -> Bool? {
        guard let value = readValue(autohideKey) else { return false }
        // Usually a boolean, but `defaults write -int` leaves an integer 0/1.
        return (value as? NSNumber)?.boolValue
    }

    func getAutohide() -> Bool {
        readAutohide() ?? false
    }

    func readSizeLock() -> Bool? {
        guard let value = readValue(sizeLockKey) else { return false }
        return (value as? NSNumber)?.boolValue
    }

    func changeSizeLock(to enabled: Bool) -> ChangeResult {
        let previous = readValue(sizeLockKey)
        guard let current = readSizeLock() else { return .notSaved }
        if current == enabled { return .applied }
        guard writeValue(sizeLockKey, enabled ? kCFBooleanTrue : kCFBooleanFalse),
              readSizeLock() == enabled else {
            writeValue(sizeLockKey, previous)
            return .notSaved
        }
        return restartDock() ? .applied : .savedWithoutRestart
    }

    @discardableResult
    func applySettings(profile: DLockProfile) -> Bool {
        guard setOrientation(profile.orientation), setAutohide(profile.autohide) else { return false }
        return restartDock()
    }

    /// Relocates the system Dock with a bounded synthetic edge gesture. The
    /// cursor remains visually at its starting point throughout placement.
    @MainActor
    func moveDock(to screen: NSScreen) async -> Bool {
        // A menu/button action can arrive before WindowServer reports release.
        // Wait for release instead of rejecting the user's display selection.
        for _ in 0..<20 {
            if !DockPlacementSession.isMouseButtonDown { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !DockPlacementSession.isMouseButtonDown,
              !CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate),
              let displayID = screen.directDisplayID,
              let original = CGEvent(source: nil)?.location else { return false }

        let bounds = CGDisplayBounds(displayID)
        guard let edge = Self.placementPoint(in: bounds, orientation: getOrientation(),
            displays: NSScreen.screens.compactMap { $0.directDisplayID.map(CGDisplayBounds) }) else { return false }
        let inward: CGVector
        switch getOrientation() {
        case .bottom:
            inward = CGVector(dx: 0, dy: -24)
        case .left:
            inward = CGVector(dx: 24, dy: 0)
        case .right:
            inward = CGVector(dx: -24, dy: 0)
        }
        // A new Dock PID can appear before it is ready to handle the shortcut.
        // Wait for its accessibility hierarchy before toggling auto-hide.
        for _ in 0..<20 {
            if DockGuardian.shared.currentDockScreen() != nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let wasHidden = getAutohide()
        if !wasHidden && changeAutohide(to: true) != .applied { return false }
        let placement = DockPlacementSession(original: original)
        guard placement.start() else {
            if !wasHidden { _ = changeAutohide(to: false) }
            return false
        }
        // Keep restoration in a synchronous defer: cancellation and every early
        // exit must put the real pointer back and remove the cursor overlay.
        var restoredAutohide = false
        defer {
            placement.finish()
            if !wasHidden && !restoredAutohide { _ = changeAutohide(to: false) }
        }
        placement.send(to: CGPoint(x: edge.x + inward.dx, y: edge.y + inward.dy))
        try? await Task.sleep(nanoseconds: 80_000_000)
        var observedTarget = false
        for _ in 0..<40 {
            guard !Task.isCancelled, !placement.cancelled,
                  NSScreen.screen(matching: screen.displayID) != nil else { return false }
            placement.send(to: edge, delta: CGVector(dx: -inward.dx, dy: -inward.dy))
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return false }
            guard !placement.cancelled else { return false }
            if DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID {
                observedTarget = true
                break
            }
        }
        // Restore the pointer before restoring auto-hide, so no later cleanup
        // can leave it at a synthetic destination.
        placement.finish()
        if !wasHidden {
            restoredAutohide = changeAutohide(to: false) == .applied
            guard restoredAutohide else { return false }
            try? await Task.sleep(nanoseconds: 150_000_000)
            return observedTarget && DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID
        }
        return observedTarget
    }

    /// Choose the longest exposed edge segment, avoiding seams between displays.
    static func placementPoint(in bounds: CGRect, orientation: DockOrientation,
                               displays: [CGRect]) -> CGPoint? {
        DockLayoutGeometry.placementPoint(in: bounds, orientation: orientation, displays: displays)
    }

    // MARK: - Preferences

    // Dlock is not sandboxed, so it reads and writes the Dock's domain directly
    // through cfprefsd. Synchronizing first drops any cached copy so changes
    // made by System Settings or the Dock itself are always observed.
    private func readValue(_ key: CFString) -> CFPropertyList? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain)
    }

    @discardableResult
    private func writeValue(_ key: CFString, _ value: CFPropertyList?) -> Bool {
        CFPreferencesSetAppValue(key, value, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            print("Dlock: could not save Dock preference \(key)")
            return false
        }
        return true
    }
}

/// A short-lived presentation and event boundary for one placement operation.
/// All callbacks run on the main run loop; no user input is consumed or clicked.
final class DockPlacementSession {
    static let eventMarker: Int64 = 0x444C4F434B504C43
    static var isMouseButtonDown: Bool {
        [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
    }

    private let original: CGPoint
    private var restorePoint: CGPoint
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cursorPanel: NSPanel?
    private var hidden = false
    private var finished = false
    private(set) var cancelled = false

    init(original: CGPoint) {
        self.original = original
        self.restorePoint = original
    }

    func start() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown,
            .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard source != nil,
              let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    let session = Unmanaged<DockPlacementSession>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        session.cancelled = true
                    } else {
                        session.handleRealInput(event, type: type)
                    }
                    return Unmanaged.passUnretained(event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = loopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Show the current cursor at its original screen position while the
        // real cursor services the system Dock. No screenshot is captured.
        let cursor = NSCursor.currentSystem ?? .arrow
        let image = cursor.image
        let desktopTop = CGDisplayBounds(CGMainDisplayID()).height
        let frame = NSRect(x: original.x - cursor.hotSpot.x,
                           y: desktopTop - original.y - image.size.height + cursor.hotSpot.y,
                           width: image.size.width, height: image.size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        panel.contentView = imageView
        cursorPanel = panel
        guard CGDisplayHideCursor(CGMainDisplayID()) == .success else {
            finish()
            return false
        }
        hidden = true
        panel.orderFrontRegardless()
        return true
    }

    func send(to point: CGPoint, delta: CGVector = .zero) {
        guard !finished, !cancelled,
              let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        CGWarpMouseCursorPosition(point)
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy))
        event.post(tap: .cgSessionEventTap)
    }

    private func handleRealInput(_ event: CGEvent, type: CGEventType) {
        guard !finished,
              event.getIntegerValueField(.eventSourceUserData) != Self.eventMarker else { return }
        // Hardware input cancels placement. Rebase it to the original cursor
        // position so a click/scroll cannot land on the synthetic Dock target.
        if !cancelled {
            switch type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                restorePoint.x += CGFloat(event.getIntegerValueField(.mouseEventDeltaX))
                restorePoint.y += CGFloat(event.getIntegerValueField(.mouseEventDeltaY))
            default: break
            }
            cancelled = true
            event.location = restorePoint
            finish()
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        CGWarpMouseCursorPosition(restorePoint)
        if let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                               mouseCursorPosition: restorePoint, mouseButton: .left) {
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
            event.post(tap: .cgSessionEventTap)
        }
        cursorPanel?.orderOut(nil)
        cursorPanel = nil
        if hidden {
            CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }
}
