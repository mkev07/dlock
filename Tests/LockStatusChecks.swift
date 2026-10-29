import AppKit

/// Pure status decisions, without accessing the Dock or injecting input.
@main struct LockStatusChecks {
    @MainActor static func main() {
        let cases: [(String, Bool, String?, String?, [String], Bool, DlockPanelModel.LockStatus)] = [
            ("confirmed placement and active guard", true, "a", "a", ["a", "b"], true, .locked),
            ("active guard with wrong display", true, "a", "b", ["a", "b"], true, .attention),
            ("active guard with unreadable location", true, "a", nil, ["a", "b"], true, .attention),
            ("matching display without guard", true, "a", "a", ["a", "b"], false, .attention),
            ("permission missing", false, "a", "a", ["a", "b"], true, .needsAccess),
            ("no selected display", true, nil, "a", ["a", "b"], false, .unlocked),
            ("selected display disconnected", true, "a", "b", ["b", "c"], true, .attention),
            ("one connected display", true, "a", "a", ["a"], false, .singleDisplay),
            ("external display confirmed", true, "b", "b", ["a", "b"], true, .locked)
        ]
        var failures = 0
        for (name, access, pinned, dock, connected, active, expected) in cases {
            let actual = DlockPanelModel.resolveLockStatus(hasAccess: access,
                pinnedDisplayID: pinned, dockDisplayID: dock,
                connectedDisplayIDs: connected, guardActive: active)
            if actual == expected { print("PASS: \(name)") }
            else { print("FAIL: \(name): \(actual)"); failures += 1 }
        }
        var state = DlockPanelModel.State()
        state.displays = [.init(id: "a", name: "Test", frame: .zero, isMain: true, isBuiltIn: true)]
        state.pinnedDisplayID = "a"
        if !state.isLocked && !state.canUseDockFeatures { print("PASS: saved pin cannot enable unlicensed controls") }
        else { failures += 1 }
        state.isLicensed = true
        if state.isLocked && state.canUseDockFeatures { print("PASS: licensed state permits controls") }
        else { failures += 1 }
        state.status = .needsAccess
        if !state.canUseDockFeatures { print("PASS: license alone does not bypass Accessibility permission") }
        else { failures += 1 }
        exit(failures == 0 ? 0 : 1)
    }
}
