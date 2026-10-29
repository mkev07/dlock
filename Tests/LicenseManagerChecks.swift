import AppKit

@main struct LicenseManagerChecks {
    @MainActor static func main() async throws {
        var stored: LicenseCredential?
        var status = 200
        var failNetwork = false
        var requests = 0
        let signer = LicenseTestSigner()
        let manager = LicenseManager(loadCredential: { stored }, saveCredential: { stored = $0 }, verifier: signer.verifier, send: { request in
            requests += 1
            if failNetwork { throw URLError(.notConnectedToInternet) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            precondition(["DLOCK-LOCAL-TEST-ONLY", "DLOCK-REPLACEMENT-KEY"].contains(body["license_key"] ?? ""))
            let payload: [String: Any] = status == 200 ? try signer.response(for: request) : ["error": "Fixture denial"]
            return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        manager.load()
        precondition(!manager.isUnlocked)
        var transitions: [Bool] = []
        manager.onAccessChange = { transitions.append($0) }
        await manager.perform("activate")
        precondition(requests == 0)
        manager.enteredKey = "DLOCK-LOCAL-TEST-ONLY"
        await manager.perform("activate")
        precondition(manager.hasActivation && stored?.activationID == "fixture-activation" && manager.enteredKey.isEmpty)
        precondition(manager.isUnlocked && transitions == [true])
        print("PASS: activation persisted through injected credential store, not real Keychain")
        let installation = stored!.installationID
        status = 403
        await manager.perform("validate")
        precondition(manager.message == "Fixture denial" && manager.hasActivation)
        precondition(!manager.isUnlocked && transitions == [true, false])
        print("PASS: invalid validation reports denial and retains transfer credentials")
        failNetwork = true
        await manager.perform("deactivate")
        precondition(manager.hasActivation && stored?.activationID != nil)
        print("PASS: failed offline deactivation does not discard activation")
        failNetwork = false
        status = 200
        await manager.perform("validate")
        precondition(manager.isUnlocked)
        failNetwork = true
        await manager.perform("validate")
        precondition(manager.isUnlocked)
        print("PASS: transient outage preserves already-verified session access")
        failNetwork = false
        await manager.perform("deactivate")
        precondition(!manager.hasActivation && !manager.hasSavedKey && stored?.key == "" && stored?.installationID == installation)
        precondition(!manager.isUnlocked)
        print("PASS: confirmed deactivation clears license but preserves installation identity")
        let reopened = LicenseManager(loadCredential: { LicenseCredential(installationID: installation, key: "fixture", activationID: "saved") }, saveCredential: { _ in })
        reopened.load()
        precondition(reopened.hasActivation && reopened.message.contains("Check validity") && !reopened.isUnlocked)
        print("PASS: restored credentials are not described as currently verified")
        let locked = LicenseManager(loadCredential: { throw LicenseClientError.keychain }, saveCredential: { _ in throw LicenseClientError.keychain })
        locked.load()
        precondition(locked.message.contains("Keychain"))
        print("PASS: Keychain errors are surfaced")
        let offlineStartup = LicenseManager(loadCredential: { LicenseCredential(installationID: installation, key: "fixture", activationID: "saved") }, saveCredential: { _ in }, send: { _ in throw URLError(.notConnectedToInternet) })
        offlineStartup.load()
        await offlineStartup.perform("validate")
        precondition(!offlineStartup.isUnlocked && offlineStartup.hasActivation)
        print("PASS: offline startup never unlocks from an unverified stored activation")
        let beforeBlocked = requests
        manager.isFeatureOperationInProgress = true
        await manager.perform("activate")
        precondition(requests == beforeBlocked && !manager.isUnlocked)
        print("PASS: license changes blocked during in-flight Dock mutation")
        manager.isFeatureOperationInProgress = false
        status = 403
        manager.enteredKey = "DLOCK-LOCAL-TEST-ONLY"
        await manager.perform("activate")
        precondition(manager.hasSavedKey && !manager.hasActivation && !manager.isUnlocked)
        status = 200
        manager.enteredKey = "DLOCK-REPLACEMENT-KEY"
        await manager.perform("activate")
        precondition(stored?.key == "DLOCK-REPLACEMENT-KEY" && manager.isUnlocked)
        print("PASS: failed activation can be corrected by pasting a replacement key")
    }
}
