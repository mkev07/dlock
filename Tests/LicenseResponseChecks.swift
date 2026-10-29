import Foundation

@main struct LicenseResponseChecks {
    static func main() throws {
        func response(status: String = "active", environment: String = "mock", activation: String? = "instance", macs: Int = 1, updates: Bool = true, expiry: String? = nil) throws -> LicenseResponse {
            var body: [String: Any] = ["status": status, "environment": environment, "all_future_updates": updates, "max_macs": macs]
            if let activation { body["activation_id"] = activation }
            if let expiry { body["expires_at"] = expiry }
            return try JSONDecoder().decode(LicenseResponse.self, from: JSONSerialization.data(withJSONObject: body))
        }
        try response().validate(for: "activate")
        try response(environment: "dodo-test").validate(for: "validate")
        try response(status: "deactivated", activation: nil).validate(for: "deactivate")
        let invalid = [try response(environment: "live"), try response(activation: nil), try response(macs: 2), try response(updates: false), try response(expiry: "2027-01-01"), try response(status: "deactivated")]
        for value in invalid {
            do { try value.validate(for: "activate"); fatalError("Invalid entitlement accepted") }
            catch LicenseClientError.invalidResponse { }
        }
        print("PASS: mock activation, sandbox validation, deactivation and six invalid entitlement responses")
    }
}
