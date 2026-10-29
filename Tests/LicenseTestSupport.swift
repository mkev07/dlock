import Foundation
import CryptoKit

struct LicenseTestSigner {
    let key = P256.Signing.PrivateKey()

    var verifier: LicenseEntitlementVerifier {
        LicenseEntitlementVerifier(publicKeys: ["fixture": key.publicKey.x963Representation], environments: ["mock"])
    }

    func sign(_ claims: LicenseEntitlement) throws -> SignedLicenseEntitlement {
        let data = try JSONEncoder().encode(claims)
        return SignedLicenseEntitlement(keyID: "fixture", payload: data.base64EncodedString(),
            signature: try key.signature(for: data).rawRepresentation.base64EncodedString())
    }

    func response(for request: URLRequest, at date: Date = Date()) throws -> [String: Any] {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
        var response: [String: Any] = ["status": request.url!.lastPathComponent == "deactivate" ? "deactivated" : "active",
            "environment": "mock", "activation_id": "fixture-activation", "all_future_updates": true, "max_macs": 1]
        if request.url!.lastPathComponent != "deactivate" {
            let issued = floor(date.timeIntervalSince1970)
            let claims = LicenseEntitlement(version: 1, app: "com.dlock.app", environment: "mock",
                installationID: body["installation_id"]!, activationID: "fixture-activation",
                licenseHash: SHA256.hash(data: Data(body["license_key"]!.utf8)).map { String(format: "%02x", $0) }.joined(),
                nonce: body["nonce"]!, issuedAt: issued,
                recheckAfter: issued + LicenseEntitlementVerifier.dailyInterval,
                offlineUntil: issued + LicenseEntitlementVerifier.offlineInterval)
            response["entitlement"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sign(claims)))
        }
        return response
    }
}
