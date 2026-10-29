import AppKit
import CryptoKit

@MainActor final class OfflineFixture {
    let signer = LicenseTestSigner()
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    var monotonic: TimeInterval = 100
    var stored: LicenseCredential?
    var requests = 0
    var offline = false
    var status = 200
    var unsigned = false
    var storageFailure = false
    var replay: Data?

    func advance(_ seconds: TimeInterval) {
        date.addTimeInterval(seconds)
        monotonic += seconds
    }

    func manager() -> LicenseManager {
        LicenseManager(loadCredential: { self.stored }, saveCredential: {
            if self.storageFailure { throw LicenseClientError.keychain }
            self.stored = $0
        }, verifier: signer.verifier, now: { self.date }, uptime: { self.monotonic }, send: { request in
            self.requests += 1
            if self.offline { throw URLError(.notConnectedToInternet) }
            var payload = self.status == 200 ? try self.signer.response(for: request, at: self.date) : ["error": "Fixture denial"]
            if self.unsigned { payload.removeValue(forKey: "entitlement") }
            return (try self.replay ?? JSONSerialization.data(withJSONObject: payload),
                HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil)!)
        })
    }

    func activate() async -> LicenseManager {
        let manager = manager()
        manager.load()
        manager.enteredKey = "DLOCK-OFFLINE-FIXTURE"
        await manager.perform("activate")
        precondition(manager.isUnlocked && stored?.entitlement != nil)
        return manager
    }
}

@main struct LicenseOfflineChecks {
    @MainActor static func main() async throws {
        let day = LicenseEntitlementVerifier.dailyInterval
        let fixture = OfflineFixture()
        let manager = await fixture.activate()
        let original = fixture.stored!
        fixture.advance(day - 1)
        await manager.refreshIfNeeded()
        precondition(fixture.requests == 1)
        fixture.advance(1)
        await manager.refreshIfNeeded()
        precondition(fixture.requests == 2 && manager.isUnlocked)
        let renewed = fixture.stored!
        precondition(renewed.entitlement?.payload != original.entitlement?.payload)
        print("PASS: no early request; renewal due exactly daily and refreshes signed window")

        fixture.offline = true
        fixture.advance(day * 29)
        let reopened = fixture.manager()
        reopened.load()
        precondition(reopened.isUnlocked)
        await reopened.refreshIfNeeded()
        let attempts = fixture.requests
        await reopened.refreshIfNeeded()
        precondition(fixture.requests == attempts && reopened.isUnlocked)
        fixture.advance(day)
        await reopened.refreshIfNeeded()
        precondition(!reopened.isUnlocked)
        let expired = fixture.manager()
        expired.load()
        precondition(!expired.isUnlocked && expired.hasActivation)
        print("PASS: offline restart works within 30 days, retries back off, exact expiry locks running and fresh sessions")
        fixture.date.addTimeInterval(-day)
        let expiredRollback = fixture.manager()
        expiredRollback.load()
        precondition(!expiredRollback.isUnlocked && fixture.stored?.clockInvalid == true)
        print("PASS: an observed expiry is checkpointed and cannot be undone by rolling the clock back")

        let outage = OfflineFixture()
        let outageManager = await outage.activate()
        let outageToken = outage.stored!.entitlement!.payload
        outage.advance(day)
        outage.status = 503
        await outageManager.refreshIfNeeded()
        precondition(outageManager.isUnlocked && outage.stored!.entitlement!.payload == outageToken)
        outage.advance(day * 29)
        await outageManager.refreshIfNeeded()
        precondition(!outageManager.isUnlocked)
        print("PASS: HTTP outages preserve but never extend the signed offline allowance")

        let revoked = OfflineFixture()
        let revokedManager = await revoked.activate()
        revoked.status = 403
        await revokedManager.perform("validate")
        precondition(!revokedManager.isUnlocked && revoked.stored?.entitlement == nil)
        revoked.offline = true
        let revokedRestart = revoked.manager()
        revokedRestart.load()
        precondition(!revokedRestart.isUnlocked && revokedRestart.hasActivation)
        print("PASS: confirmed denial removes cached access across restart while preserving transfer credentials")

        let rollback = OfflineFixture()
        let rollbackManager = await rollback.activate()
        rollback.advance(day / 2)
        await rollbackManager.refreshIfNeeded()
        rollback.offline = true
        rollback.date.addTimeInterval(-3600)
        await rollbackManager.refreshIfNeeded()
        precondition(!rollbackManager.isUnlocked && rollback.stored?.clockInvalid == true)
        rollback.advance(3600)
        let rollbackRestart = rollback.manager()
        rollbackRestart.load()
        precondition(!rollbackRestart.isUnlocked)
        rollback.offline = false
        await rollbackRestart.perform("validate")
        precondition(rollbackRestart.isUnlocked && rollback.stored?.clockInvalid == false)
        rollback.monotonic += 601
        await rollbackRestart.refreshIfNeeded()
        precondition(!rollbackRestart.isUnlocked)
        print("PASS: persisted rollback latch requires fresh online verification; frozen wall clock detected using uptime")

        let replay = OfflineFixture()
        let replayManager = await replay.activate()
        var fakeRequest = URLRequest(url: URL(string: "http://localhost/validate")!)
        fakeRequest.httpBody = try JSONEncoder().encode(["installation_id": replay.stored!.installationID,
            "license_key": replay.stored!.key, "nonce": "wrong-old-request-nonce"])
        replay.replay = try JSONSerialization.data(withJSONObject: replay.signer.response(for: fakeRequest, at: replay.date))
        replay.advance(day * 30)
        await replayManager.perform("validate")
        precondition(!replayManager.isUnlocked)
        print("PASS: replayed response cannot refresh an expired entitlement")

        let missing = OfflineFixture()
        missing.unsigned = true
        let missingManager = missing.manager()
        missingManager.load()
        missingManager.enteredKey = "DLOCK-OFFLINE-FIXTURE"
        await missingManager.perform("activate")
        precondition(!missingManager.isUnlocked && missing.stored?.entitlement == nil)
        print("PASS: unsigned successful response cannot unlock")

        let storage = OfflineFixture()
        let storageManager = storage.manager()
        storageManager.load()
        storageManager.enteredKey = "DLOCK-OFFLINE-FIXTURE"
        storage.storageFailure = true
        await storageManager.perform("activate")
        precondition(!storageManager.isUnlocked)
        print("PASS: credential persistence failure cannot grant new access")

        let verified = try fixture.signer.verifier.verify(original.entitlement!, credential: original,
            now: Date(timeIntervalSince1970: 1_800_000_000))
        let payload = try JSONSerialization.jsonObject(with: Data(base64Encoded: original.entitlement!.payload)!) as! [String: Any]
        for (field, replacement) in [("app", "other.app"), ("version", 2), ("environment", "production"),
            ("installation_id", "other-installation"), ("activation_id", "other-activation"), ("license_hash", "wrong"),
            ("recheck_after", verified.issuedAt + day * 7), ("offline_until", verified.issuedAt + day * 31)] as [(String, Any)] {
            var changed = payload
            changed[field] = replacement
            let data = try JSONSerialization.data(withJSONObject: changed)
            let signed = SignedLicenseEntitlement(keyID: "fixture", payload: data.base64EncodedString(),
                signature: try fixture.signer.key.signature(for: data).rawRepresentation.base64EncodedString())
            do {
                _ = try fixture.signer.verifier.verify(signed, credential: original,
                    now: Date(timeIntervalSince1970: 1_800_000_000))
                fatalError("Accepted invalid field: \(field)")
            } catch { }
        }
        for signed in [SignedLicenseEntitlement(keyID: "unknown", payload: original.entitlement!.payload,
                           signature: original.entitlement!.signature),
                       SignedLicenseEntitlement(keyID: "fixture", payload: Data("{}".utf8).base64EncodedString(),
                           signature: original.entitlement!.signature),
                       SignedLicenseEntitlement(keyID: "fixture", payload: original.entitlement!.payload, signature: "invalid")] {
            do {
                _ = try fixture.signer.verifier.verify(signed, credential: original,
                    now: Date(timeIntervalSince1970: 1_800_000_000))
                fatalError("Accepted invalid signature or key")
            } catch { }
        }
        print("PASS: signature tampering, unknown signing key, wrong app/environment/bindings and altered policy rejected")

        for date in [verified.issuedAt - 301, verified.offlineUntil] {
            do {
                _ = try fixture.signer.verifier.verify(original.entitlement!, credential: original,
                    now: Date(timeIntervalSince1970: date))
                fatalError("Accepted future-issued or expired token")
            } catch { }
        }
        do {
            _ = try fixture.signer.verifier.verify(original.entitlement!, credential: original,
                now: Date(timeIntervalSince1970: verified.issuedAt), nonce: "new-request-nonce")
            fatalError("Accepted wrong nonce")
        } catch { }
        print("PASS: future issuance, exact 30-day expiry and fresh-request nonce boundaries enforced")
        do {
            _ = try fixture.signer.verifier.verify(original.entitlement!, credential: original,
                now: Date(timeIntervalSince1970: verified.issuedAt + day), nonce: verified.nonce)
            fatalError("Accepted stale online response")
        } catch { }
        print("PASS: matching nonce cannot make a stale online response fresh")

        let concurrent = OfflineFixture()
        let concurrentManager = await concurrent.activate()
        concurrentManager.isFeatureOperationInProgress = true
        concurrent.advance(day)
        let blockedRequests = concurrent.requests
        await concurrentManager.refreshIfNeeded()
        precondition(concurrent.requests == blockedRequests)
        concurrentManager.isFeatureOperationInProgress = false
        await concurrentManager.refreshIfNeeded()
        precondition(concurrent.requests == blockedRequests + 1)
        print("PASS: scheduled checks wait for Dock operations and resume when safe")
    }
}
