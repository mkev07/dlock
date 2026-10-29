import Foundation

@main struct LicenseInteropChecks {
    struct Fixture: Decodable {
        let publicKey: String
        let credential: LicenseCredential
        let entitlement: SignedLicenseEntitlement
        let issuedAt: TimeInterval
        let nonce: String
    }

    static func main() throws {
        let fixture = try JSONDecoder().decode(Fixture.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let verifier = LicenseEntitlementVerifier(publicKeys: ["test-v1": Data(base64Encoded: fixture.publicKey)!],
            environments: ["mock"])
        let claims = try verifier.verify(fixture.entitlement, credential: fixture.credential,
            now: Date(timeIntervalSince1970: fixture.issuedAt), nonce: fixture.nonce)
        precondition(claims.offlineUntil - claims.issuedAt == 30 * 86400)
        print("PASS: Swift CryptoKit verifies actual Node P256 entitlement without re-encoding its signed payload")
    }
}
