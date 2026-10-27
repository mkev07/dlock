import AppKit
import ApplicationServices
import CoreGraphics
import os

private let dockGuardEventCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let guardian = Unmanaged<DockGuardian>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        guardian.reenableEventTap()
        return Unmanaged.passUnretained(event)
    }

    guardian.filterMouseEvent(event)
    return Unmanaged.passUnretained(event)
}

final class DockGuardian {

    static let shared = DockGuardian()

    private struct GuardZone {
        let frame: CGRect
        let inwardOffset: CGVector
        let screenName: String
        let edgeName: String
    }

    private let logger = Logger(subsystem: "com.dlock.app", category: "Guardian")
    private let edgeDepth: CGFloat = 7
    private let adjacencyTolerance: CGFloat = 2

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var guardZones: [GuardZone] = []
    private(set) var interceptedEventCount = 0
    private var lastIntercept: (date: Date, original: CGPoint, adjusted: CGPoint)?
    private var tapRecoveryCount = 0
    private var lastTapRecovery: Date?

    private init() {}

    func refresh() {
        stop()

        guard AccessibilityPermission.isGranted(),
              NSScreen.screens.count > 1,
              let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey),
              NSScreen.screen(matching: pinnedID) != nil else { return }

        guardZones = buildGuardZones(pinnedID: pinnedID)
        installEventTap()
        logger.notice("guardian refreshed with \(self.guardZones.count, privacy: .public) guarded edge zones")
    }

    func pause() {
        stop()
    }

    func currentDockScreen() -> NSScreen? {
        guard AccessibilityPermission.isGranted(),
              let dockApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .first else { return nil }

        let axApp = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let element = primaryDockElement(in: axApp),
              let position = axPosition(of: element),
              let size = axSize(of: element) else { return nil }

        guard size.width > 0, size.height > 0 else { return nil }
        let probe = Self.screenProbePoint(position: position, size: size,
                                         orientation: DockController.shared.getOrientation())
        return NSScreen.screens.first { screen in
            guard let displayID = screen.directDisplayID else { return false }
            return CGDisplayBounds(displayID).contains(probe)
        }
    }

    /// Hidden Dock geometry lies beyond the display edge. Probe one point on
    /// its inward side, not the center (which may be on a neighbouring screen).
    static func screenProbePoint(position: CGPoint, size: CGSize,
                                 orientation: DockOrientation) -> CGPoint {
        switch orientation {
        case .bottom:
            return CGPoint(x: position.x + size.width / 2, y: position.y - 1)
        case .left:
            return CGPoint(x: position.x + size.width + 1, y: position.y + size.height / 2)
        case .right:
            return CGPoint(x: position.x - 1, y: position.y + size.height / 2)
        }
    }

    fileprivate func reenableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        tapRecoveryCount += 1
        lastTapRecovery = Date()
        logger.notice("re-enabled event tap after macOS disabled it")
    }

    var isGuardActive: Bool {
        guardZones.count > 0
            && NSScreen.screens.count > 1
            && UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey)
                .flatMap(NSScreen.screen(matching:)) != nil
            && eventTap.map { CGEvent.tapIsEnabled(tap: $0) } == true
            && AccessibilityPermission.isGranted()
    }

    var guardedEdgeDescriptions: [String] {
        Array(Set(guardZones.map { "\($0.screenName) · \($0.edgeName)" })).sorted()
    }

    var statusSummary: String {
        if !AccessibilityPermission.isGranted() { return "Grant Accessibility permission to enable edge protection." }
        if NSScreen.screens.count <= 1 { return "Connect a second display to enable edge protection." }
        guard let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey) else {
            return "Choose the screen where you want the Dock to stay."
        }
        guard NSScreen.screen(matching: pinnedID) != nil else {
            return "The pinned screen is unavailable. Reconnect it or choose another screen."
        }
        if guardZones.isEmpty { return "No exposed edges are available to protect in this display layout." }
        if eventTap.map({ CGEvent.tapIsEnabled(tap: $0) }) != true { return "The pointer monitor is inactive. Quit and reopen Dlock." }
        return "Protecting the exposed Dock edge on other displays."
    }

    var diagnosticsText: String {
        let tapActive = eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey)
        let pinnedName = pinnedID.flatMap { NSScreen.screen(matching: $0)?.localizedName }
            ?? UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenNameKey)
            ?? "None"
        let eligibility: String
        let recovery: String
        if !AccessibilityPermission.isGranted() {
            eligibility = "INACTIVE — Accessibility permission missing"
            recovery = "Grant Dlock Accessibility access in System Settings, then quit and reopen Dlock."
        } else if NSScreen.screens.count <= 1 {
            eligibility = "INACTIVE — only one display detected"
            recovery = "Connect a second display to enable Dock locking."
        } else if pinnedID == nil || NSScreen.screen(matching: pinnedID!) == nil {
            eligibility = "INACTIVE — pinned display unavailable"
            recovery = "Reconnect the pinned display or choose another in Dlock’s menu."
        } else if guardZones.isEmpty {
            eligibility = "INACTIVE — no exposed edge zones to guard"
            recovery = "Change the display arrangement or Dock edge, then refresh by reopening Dlock."
        } else if !tapActive {
            eligibility = "INACTIVE — event tap is unavailable"
            recovery = "Quit and reopen Dlock. If this continues, check Accessibility permission."
        } else {
            eligibility = "ACTIVE — protecting exposed edges"
            recovery = tapRecoveryCount == 0
                ? "No event tap recovery needed."
                : "Event tap recovered \(tapRecoveryCount) time(s); last at \(lastTapRecovery?.formatted(date: .omitted, time: .standard) ?? "unknown")."
        }
        let zones = guardZones.map { "• \($0.screenName): \($0.edgeName) edge" }.joined(separator: "\n")
        let last = lastIntercept.map {
            "\($0.date.formatted(date: .omitted, time: .standard)) · (\(Int($0.original.x)), \(Int($0.original.y))) → (\(Int($0.adjusted.x)), \(Int($0.adjusted.y)))"
        } ?? "None yet"
        return "Status: \(eligibility)\nPinned display: \(pinnedName)\nGuarded edges (\(guardZones.count)): \(zones.isEmpty ? "None" : "\n\(zones)")\nIntercepted pointer events: \(interceptedEventCount)\nLast adjusted event: \(last)\n\n\(recovery)\n\nThe counter records pointer events Dlock moved inward. It does not count Dock appearances; macOS does not expose that signal to Dlock."
    }

    fileprivate func filterMouseEvent(_ event: CGEvent) {
        guard event.getIntegerValueField(.eventSourceUserData) != DockPlacementSession.eventMarker else { return }
        let flags = event.flags.union(CGEventSource.flagsState(.combinedSessionState))
        guard !flags.contains(.maskAlternate) else { return }

        let location = event.location
        guard let zone = guardZones.first(where: { $0.frame.contains(location) }) else { return }
        let adjusted = CGPoint(
            x: location.x + zone.inwardOffset.dx,
            y: location.y + zone.inwardOffset.dy
        )
        event.location = adjusted
        interceptedEventCount += 1
        lastIntercept = (Date(), location, adjusted)
    }

    private func installEventTap() {
        let mask: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockGuardEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("guardian event tap could not be created")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = tap
        runLoopSource = source
    }

    private func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        guardZones = []
    }

    private func buildGuardZones(pinnedID: String) -> [GuardZone] {
        let screens = NSScreen.screens
        let frames = screens.compactMap { screen -> (screen: NSScreen, frame: CGRect)? in
            guard let displayID = screen.directDisplayID else { return nil }
            return (screen, CGDisplayBounds(displayID))
        }
        let orientation = DockController.shared.getOrientation()
        var zones: [GuardZone] = []

        for item in frames where item.screen.displayID != pinnedID {
            let currentEdgeRange = edgeRange(for: item.frame, orientation: orientation)
            let coveredRanges = frames.compactMap { other -> ClosedRange<CGFloat>? in
                guard other.screen.displayID != item.screen.displayID,
                      edgesTouch(item.frame, other.frame, orientation: orientation) else { return nil }
                return overlapRange(
                    currentEdgeRange,
                    edgeRange(for: other.frame, orientation: orientation)
                )
            }

            for exposedRange in subtract(coveredRanges, from: currentEdgeRange) {
                guard exposedRange.upperBound - exposedRange.lowerBound > 1 else { continue }
                zones.append(zone(
                    for: item.frame,
                    exposedRange: exposedRange,
                    orientation: orientation,
                    screenName: item.screen.localizedName
                ))
            }
        }

        return zones
    }

    private func edgeRange(for frame: CGRect, orientation: DockOrientation) -> ClosedRange<CGFloat> {
        switch orientation {
        case .left, .right:
            return frame.minY...frame.maxY
        case .bottom:
            return frame.minX...frame.maxX
        }
    }

    private func edgesTouch(_ frame: CGRect, _ other: CGRect, orientation: DockOrientation) -> Bool {
        switch orientation {
        case .left:
            return abs(other.maxX - frame.minX) <= adjacencyTolerance
        case .right:
            return abs(other.minX - frame.maxX) <= adjacencyTolerance
        case .bottom:
            return abs(other.minY - frame.maxY) <= adjacencyTolerance
        }
    }

    private func overlapRange(
        _ first: ClosedRange<CGFloat>,
        _ second: ClosedRange<CGFloat>
    ) -> ClosedRange<CGFloat>? {
        let lower = max(first.lowerBound, second.lowerBound)
        let upper = min(first.upperBound, second.upperBound)
        return upper > lower ? lower...upper : nil
    }

    private func subtract(
        _ coveredRanges: [ClosedRange<CGFloat>],
        from fullRange: ClosedRange<CGFloat>
    ) -> [ClosedRange<CGFloat>] {
        let sorted = coveredRanges.sorted { $0.lowerBound < $1.lowerBound }
        var exposed: [ClosedRange<CGFloat>] = []
        var cursor = fullRange.lowerBound

        for covered in sorted {
            if covered.lowerBound > cursor {
                exposed.append(cursor...min(covered.lowerBound, fullRange.upperBound))
            }
            cursor = max(cursor, covered.upperBound)
        }

        if cursor < fullRange.upperBound {
            exposed.append(cursor...fullRange.upperBound)
        }
        return exposed
    }

    private func zone(
        for frame: CGRect,
        exposedRange: ClosedRange<CGFloat>,
        orientation: DockOrientation,
        screenName: String
    ) -> GuardZone {
        switch orientation {
        case .left:
            return GuardZone(
                frame: CGRect(
                    x: frame.minX,
                    y: exposedRange.lowerBound,
                    width: edgeDepth,
                    height: exposedRange.upperBound - exposedRange.lowerBound
                ),
                inwardOffset: CGVector(dx: edgeDepth, dy: 0),
                screenName: screenName,
                edgeName: "Left"
            )
        case .right:
            return GuardZone(
                frame: CGRect(
                    x: frame.maxX - edgeDepth,
                    y: exposedRange.lowerBound,
                    width: edgeDepth,
                    height: exposedRange.upperBound - exposedRange.lowerBound
                ),
                inwardOffset: CGVector(dx: -edgeDepth, dy: 0),
                screenName: screenName,
                edgeName: "Right"
            )
        case .bottom:
            return GuardZone(
                frame: CGRect(
                    x: exposedRange.lowerBound,
                    y: frame.maxY - edgeDepth,
                    width: exposedRange.upperBound - exposedRange.lowerBound,
                    height: edgeDepth
                ),
                inwardOffset: CGVector(dx: 0, dy: -edgeDepth),
                screenName: screenName,
                edgeName: "Bottom"
            )
        }
    }

    private func primaryDockElement(in axApp: AXUIElement) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
        let children = childrenRef as? [AXUIElement] else { return nil }

        return children
            .filter { axString(of: $0, attribute: kAXRoleAttribute as CFString) == kAXListRole }
            .max { (axArea(of: $0) ?? 0) < (axArea(of: $1) ?? 0) }
            ?? children.max { (axArea(of: $0) ?? 0) < (axArea(of: $1) ?? 0) }
    }

    private func axArea(of element: AXUIElement) -> CGFloat? {
        axSize(of: element).map { $0.width * $0.height }
    }

    private func axPosition(of element: AXUIElement) -> CGPoint? {
        guard let value = axValue(of: element, attribute: kAXPositionAttribute as CFString) else { return nil }
        var position = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &position) ? position : nil
    }

    private func axSize(of element: AXUIElement) -> CGSize? {
        guard let value = axValue(of: element, attribute: kAXSizeAttribute as CFString) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func axValue(of element: AXUIElement, attribute: CFString) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref,
              CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(ref, to: AXValue.self)
    }

    private func axString(of element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }
}
