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
    }

    private let logger = Logger(subsystem: "com.dlock.app", category: "Guardian")
    private let edgeDepth: CGFloat = 7
    private let adjacencyTolerance: CGFloat = 2

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var guardZones: [GuardZone] = []

    private init() {}

    func refresh() {
        stop()

        guard AccessibilityPermission.isGranted(),
              NSScreen.screens.count > 1,
              let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey),
              NSScreen.screen(matching: pinnedID) != nil else { return }

        guardZones = buildGuardZones(pinnedID: pinnedID)
        installEventTap()
        logger.notice("guardian active with \(self.guardZones.count, privacy: .public) guarded edge zones")
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

        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        return NSScreen.screens.first { screen in
            guard let displayID = screen.directDisplayID else { return false }
            return CGDisplayBounds(displayID).contains(center)
        }
    }

    fileprivate func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func filterMouseEvent(_ event: CGEvent) {
        let flags = event.flags.union(CGEventSource.flagsState(.combinedSessionState))
        guard !flags.contains(.maskAlternate) else { return }

        let location = event.location
        guard let zone = guardZones.first(where: { $0.frame.contains(location) }) else { return }
        event.location = CGPoint(
            x: location.x + zone.inwardOffset.dx,
            y: location.y + zone.inwardOffset.dy
        )
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
                    orientation: orientation
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
        orientation: DockOrientation
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
                inwardOffset: CGVector(dx: edgeDepth, dy: 0)
            )
        case .right:
            return GuardZone(
                frame: CGRect(
                    x: frame.maxX - edgeDepth,
                    y: exposedRange.lowerBound,
                    width: edgeDepth,
                    height: exposedRange.upperBound - exposedRange.lowerBound
                ),
                inwardOffset: CGVector(dx: -edgeDepth, dy: 0)
            )
        case .bottom:
            return GuardZone(
                frame: CGRect(
                    x: exposedRange.lowerBound,
                    y: frame.maxY - edgeDepth,
                    width: exposedRange.upperBound - exposedRange.lowerBound,
                    height: edgeDepth
                ),
                inwardOffset: CGVector(dx: 0, dy: -edgeDepth)
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
