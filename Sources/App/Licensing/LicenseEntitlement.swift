import Foundation
import CryptoKit

struct SignedLicenseEntitlement: Codable {
    let keyID: String
    let payload: String
    let signature: String

    enum CodingKeys: String, CodingKey {
        case keyID = "key_id"
        case payload, signature
    }
}

struct LicenseEntitlement: Codable {
    let version: Int
    let app: String
    let environment: String
    let installationID: String
    let activationID: String
    let licenseHash: String
    let nonce: String
    let issuedAt: TimeInterval
    let recheckAfter: TimeInterval
    let offlineUntil: TimeInterval

    enum CodingKeys: String, CodingKey {
        case version, app, environment, nonce
        case installationID = "installation_id"
        case activationID = "activation_id"
        case licenseHash = "license_hash"
        case issuedAt = "issued_at"
        case recheckAfter = "recheck_after"
        case offlineUntil = "offline_until"
    }
}

struct LicenseEntitlementVerifier {
    static let dailyInterval: TimeInterval = 24 * 60 * 60
    static let offlineInterval: TimeInterval = 30 * dailyInterval
    static let clockTolerance: TimeInterval = 5 * 60
    let publicKeys: [String: Data]
    let environments: Set<String>

    static var configured: Self {
        #if DEBUG
        return Self(publicKeys: ["test-v1": Data(base64Encoded: "BOXjlVIHT1DfYFOehlEHuwocU0aQazir5Yioh/Olx+6oZQJonnunP7BqtGRlv2/8kMiKwCiMyinf1JBPTZN5tz4=")!],
                    environments: ["mock", "dodo-test"])
        #else
        return Self(publicKeys: [:], environments: [])
        #endif
    }

    func verify(_ signed: SignedLicenseEntitlement, credential: LicenseCredential,
                now: Date, nonce: String? = nil) throws -> LicenseEntitlement {
        guard let keyData = publicKeys[signed.keyID], signed.payload.utf8.count <= 8192,
              let payload = Data(base64Encoded: signed.payload),
              let signature = Data(base64Encoded: signed.signature), signature.count == 64 else {
            throw LicenseClientError.invalidResponse
        }
        let key = try P256.Signing.PublicKey(x963Representation: keyData)
        guard key.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: payload) else {
            throw LicenseClientError.invalidResponse
        }
        let claims = try JSONDecoder().decode(LicenseEntitlement.self, from: payload)
        let instant = now.timeIntervalSince1970
        let hash = SHA256.hash(data: Data(credential.key.utf8)).map { String(format: "%02x", $0) }.joined()
        guard claims.version == 1, claims.app == "com.dlock.app", environments.contains(claims.environment),
              claims.installationID == credential.installationID, claims.activationID == credential.activationID,
              claims.licenseHash == hash, claims.issuedAt.isFinite, claims.issuedAt >= 0,
              claims.recheckAfter == claims.issuedAt + Self.dailyInterval,
              claims.offlineUntil == claims.issuedAt + Self.offlineInterval,
              instant >= claims.issuedAt - Self.clockTolerance, instant < claims.offlineUntil,
              nonce == nil || (claims.nonce == nonce && abs(instant - claims.issuedAt) <= Self.clockTolerance) else {
            throw LicenseClientError.invalidResponse
        }
        return claims
    }
}
