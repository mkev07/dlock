import AppKit

@main struct LicenseReleaseChecks {
    @MainActor static func main() async {
        var requests = 0
        let manager = LicenseManager(loadCredential: {
            LicenseCredential(installationID: "release-fixture", key: "DLOCK-LOCAL-TEST-ONLY", activationID: "fixture")
        }, saveCredential: { _ in }, send: { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        })
        manager.load()
        await manager.perform("validate")
        await manager.refreshIfNeeded()
        precondition(!manager.isConfigured && !manager.isUnlocked && requests == 0)
        precondition(LicenseEntitlementVerifier.configured.publicKeys.isEmpty)
        let injected = LicenseManager(loadCredential: { nil }, saveCredential: { _ in },
            verifier: LicenseEntitlementVerifier(publicKeys: ["fixture": Data(repeating: 1, count: 65)], environments: ["mock"]),
            send: { _ in requests += 1; throw URLError(.notConnectedToInternet) })
        injected.load()
        injected.enteredKey = "DLOCK-LOCAL-TEST-ONLY"
        await injected.perform("activate")
        precondition(!injected.isConfigured && !injected.isUnlocked && requests == 0)
        print("PASS: Release rejects test configuration and never contacts loopback licensing")
    }
}
