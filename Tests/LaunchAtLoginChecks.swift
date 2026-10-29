import Foundation
import ServiceManagement

@main struct LaunchAtLoginChecks {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ name: String) {
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }
        var status = SMAppService.Status.notRegistered
        var registrations = 0
        var removals = 0
        var registrationStatus = SMAppService.Status.enabled
        var shouldFail = false
        let manager = LaunchAtLoginManager(readStatus: { status }, register: {
            registrations += 1
            if shouldFail { throw NSError(domain: "LoginTest", code: 1) }
            status = registrationStatus
        }, unregister: {
            removals += 1
            if shouldFail { throw NSError(domain: "LoginTest", code: 2) }
            status = .notRegistered
        })
        check(!manager.isEnabled, "unregistered is unchecked")
        check(manager.toggle() == .enabled && manager.isEnabled && registrations == 1, "register and read actual status")
        status = .notRegistered
        check(!manager.isEnabled, "external disable reflected without saved preference")
        registrationStatus = .requiresApproval
        check(manager.toggle() == .requiresApproval && !manager.isEnabled && manager.requiresApproval, "approval is not enabled")
        check(manager.toggle() == .disabled && removals == 1, "pending approval can be cancelled")
        shouldFail = true
        if case .failed = manager.toggle() { check(!manager.isEnabled, "registration error does not enable") }
        else { check(false, "registration error surfaced") }
        status = .enabled
        if case .failed = manager.toggle() { check(manager.isEnabled, "unregister error preserves actual enabled status") }
        else { check(false, "unregister error surfaced") }
        shouldFail = false
        check(manager.toggle() == .disabled && !manager.isEnabled, "unregister enabled service")
        registrationStatus = .notFound
        check(manager.toggle() == .unavailable && !manager.isEnabled, "missing login item not shown as enabled")
        registrationStatus = .enabled
        check(manager.toggle() == .enabled && manager.isEnabled, "missing login item can retry registration")
        exit(failures == 0 ? 0 : 1)
    }
}
