import AppKit
import Combine
import Security

struct LicenseCredential: Codable {
    var installationID: String
    var key: String
    var activationID: String?
    var entitlement: SignedLicenseEntitlement?
    var lastSeenAt: TimeInterval?
    var clockInvalid: Bool?
    var offlineBlocked: Bool?
}

enum LicenseKeychain {
    #if DEBUG
    private static let service = "com.dlock.licensing.test.v1"
    private static let account = "local-test"
    #else
    private static let service = "com.dlock.licensing.production.v1"
    private static let account = "license"
    #endif
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]

    static func load() throws -> LicenseCredential? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw LicenseClientError.keychain }
        return try JSONDecoder().decode(LicenseCredential.self, from: data)
    }

    static func save(_ credential: LicenseCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw LicenseClientError.keychain }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LicenseClientError.keychain }
    }
}

enum LicenseClientError: LocalizedError {
    case keychain, invalidResponse, unconfigured
    var errorDescription: String? {
        switch self {
        case .keychain: return "Could not access Dlock’s test license in Keychain. Your saved activation was not removed."
        case .invalidResponse: return "The test service returned an unexpected response. Your saved activation was retained."
        case .unconfigured: return "Production licensing is not configured. Dock features remain disabled."
        }
    }
}

struct LicenseResponse: Decodable {
    let status: String
    let environment: String
    let activationID: String?
    let allFutureUpdates: Bool
    let maxMacs: Int
    let expiresAt: String?
    let entitlement: SignedLicenseEntitlement?

    enum CodingKeys: String, CodingKey {
        case status, environment, entitlement
        case activationID = "activation_id"
        case allFutureUpdates = "all_future_updates"
        case maxMacs = "max_macs"
        case expiresAt = "expires_at"
    }

    func validate(for action: String) throws {
        #if DEBUG
        let allowedEnvironments = ["mock", "dodo-test"]
        #else
        let allowedEnvironments: [String] = []
        #endif
        guard allowedEnvironments.contains(environment), maxMacs == 1, allFutureUpdates,
              expiresAt == nil,
              (action == "deactivate" ? status == "deactivated" : (status == "active" && !(activationID ?? "").isEmpty))
        else { throw LicenseClientError.invalidResponse }
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    typealias Send = (URLRequest) async throws -> (Data, URLResponse)
    @Published var enteredKey = ""
    @Published private(set) var message = "Activate a test license to enable Dock features."
    @Published private(set) var isUnlocked = false {
        didSet { if oldValue != isUnlocked { onAccessChange?(isUnlocked) } }
    }
    var onAccessChange: ((Bool) -> Void)?
    var isFeatureOperationInProgress = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasActivation = false
    @Published private(set) var hasSavedKey = false
    private var credential: LicenseCredential?
    private var loaded = false
    private let loadCredential: () throws -> LicenseCredential?
    private let saveCredential: (LicenseCredential) throws -> Void
    private let send: Send
    private let verifier: LicenseEntitlementVerifier
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var anchorWall: TimeInterval?
    private var anchorUptime: TimeInterval?
    private var lastCheckpoint: TimeInterval?
    private var lastAttempt: TimeInterval?

    init(loadCredential: @escaping () throws -> LicenseCredential? = { try LicenseKeychain.load() },
         saveCredential: @escaping (LicenseCredential) throws -> Void = { try LicenseKeychain.save($0) },
         verifier: LicenseEntitlementVerifier = .configured,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         send: @escaping Send = { request in
             let configuration = URLSessionConfiguration.ephemeral
             let session = URLSession(configuration: configuration)
             defer { session.finishTasksAndInvalidate() }
             return try await session.data(for: request)
         }) {
        self.loadCredential = loadCredential
        self.saveCredential = saveCredential
        self.send = send
        self.verifier = verifier
        self.now = now
        self.uptime = uptime
    }

    var isConfigured: Bool {
        #if DEBUG
        return !verifier.publicKeys.isEmpty
        #else
        return false
        #endif
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        do {
            credential = try loadCredential()
            updateSavedState()
            if hasSavedKey { message = "Saved test license. Check validity to verify its current status." }
            _ = evaluateOfflineAccess()
        } catch {
            message = error.localizedDescription
        }
    }

    func perform(_ action: String) async {
        guard ["activate", "validate", "deactivate"].contains(action) else { return }
        guard !isBusy else { return }
        guard !isFeatureOperationInProgress else { message = "Wait for the Dock operation to finish, then retry."; return }
        guard isConfigured else { message = LicenseClientError.unconfigured.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        lastAttempt = uptime()
        do {
            if credential == nil { credential = LicenseCredential(installationID: UUID().uuidString, key: "", activationID: nil) }
            guard var saved = credential else { throw LicenseClientError.keychain }
            if action == "activate", saved.activationID == nil,
               (saved.key.isEmpty || !enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                let key = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard key.count >= 8, key.count <= 512 else { message = "Enter a valid test license key."; return }
                saved.key = key
                try saveCredential(saved)
                credential = saved
                enteredKey = ""
                updateSavedState()
            }
            guard !saved.key.isEmpty else { message = "Enter a test license key first."; return }
            #if DEBUG
            let endpoint = URL(string: "http://127.0.0.1:8787/v1/licenses/\(action)")!
            #else
            throw LicenseClientError.unconfigured
            #endif
            #if DEBUG
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let nonce = UUID().uuidString
            var body = ["license_key": saved.key, "installation_id": saved.installationID, "nonce": nonce]
            if let activation = saved.activationID { body["activation_id"] = activation }
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await send(request)
            guard let response = response as? HTTPURLResponse else { throw LicenseClientError.invalidResponse }
            guard response.statusCode == 200 else {
                if [401, 403, 409, 410].contains(response.statusCode) {
                    isUnlocked = false
                    saved.entitlement = nil
                    saved.offlineBlocked = true
                    credential = saved
                    try saveCredential(saved)
                } else { _ = evaluateOfflineAccess() }
                struct Failure: Decodable { let error: String }
                let failure = try? JSONDecoder().decode(Failure.self, from: data)
                message = failure?.error ?? "Test service failed (HTTP \(response.statusCode)). Saved activation retained."
                return
            }
            let result = try JSONDecoder().decode(LicenseResponse.self, from: data)
            try result.validate(for: action)
            if action == "deactivate" {
                isUnlocked = false
                saved.key = ""
                saved.activationID = nil
                saved.entitlement = nil
                saved.offlineBlocked = true
                credential = saved
            } else {
                guard action != "validate" || result.activationID == saved.activationID,
                      let entitlement = result.entitlement else { throw LicenseClientError.invalidResponse }
                saved.activationID = result.activationID
                let claims = try verifier.verify(entitlement, credential: saved, now: now(), nonce: nonce)
                guard claims.environment == result.environment else { throw LicenseClientError.invalidResponse }
                saved.entitlement = entitlement
                saved.lastSeenAt = now().timeIntervalSince1970
                saved.clockInvalid = false
                saved.offlineBlocked = false
            }
            try saveCredential(saved)
            credential = saved
            updateSavedState()
            anchorWall = saved.lastSeenAt
            anchorUptime = uptime()
            lastCheckpoint = uptime()
            if action != "deactivate" { isUnlocked = true }
            let environment = result.environment == "mock" ? "Local simulation" : "Dodo sandbox"
            message = action == "deactivate" ? "\(environment): deactivated. The license can be activated on another Mac." : "\(environment): active. Lifetime license, all future updates. Checks daily; up to 30 days offline after verification."
            #endif
        } catch {
            _ = evaluateOfflineAccess()
            message = "\(error.localizedDescription) Saved activation retained."
        }
    }

    func refreshIfNeeded() async {
        load()
        let claims = evaluateOfflineAccess()
        guard hasActivation, !isBusy, !isFeatureOperationInProgress else { return }
        guard claims == nil || now().timeIntervalSince1970 >= claims!.recheckAfter else { return }
        if let lastAttempt, uptime() - lastAttempt < 15 * 60 { return }
        await perform("validate")
    }

    @discardableResult
    private func evaluateOfflineAccess() -> LicenseEntitlement? {
        guard isConfigured, var saved = credential, saved.offlineBlocked != true,
              let signed = saved.entitlement else { isUnlocked = false; return nil }
        let instant = now().timeIntervalSince1970
        let monotonic = uptime()
        if anchorWall == nil {
            anchorWall = max(instant, saved.lastSeenAt ?? instant)
            anchorUptime = monotonic
        }
        let expected = max(saved.lastSeenAt ?? instant,
                           (anchorWall ?? instant) + max(0, monotonic - (anchorUptime ?? monotonic)))
        if instant < expected - LicenseEntitlementVerifier.clockTolerance { saved.clockInvalid = true }
        if saved.clockInvalid == true {
            isUnlocked = false
            credential = saved
            try? saveCredential(saved)
            message = "Your Mac’s clock changed. Connect to verify your license again."
            return nil
        }
        do {
            if lastCheckpoint == nil || monotonic - lastCheckpoint! >= 5 * 60 {
                saved.lastSeenAt = max(instant, saved.lastSeenAt ?? instant)
                try saveCredential(saved)
                credential = saved
                lastCheckpoint = monotonic
            }
            let claims = try verifier.verify(signed, credential: saved, now: now())
            isUnlocked = true
            message = "License active. Checks daily; up to 30 days offline after successful verification."
            return claims
        } catch {
            isUnlocked = false
            message = "Connect to verify your license. Offline access is expired or could not be verified."
            return nil
        }
    }

    func clearUnactivatedKey() {
        guard !isBusy, !hasActivation, var saved = credential else { return }
        do {
            saved.key = ""
            try saveCredential(saved)
            credential = saved
            updateSavedState()
            message = "Unactivated test key cleared."
        } catch { message = error.localizedDescription }
    }

    private func updateSavedState() {
        hasActivation = credential?.activationID != nil
        hasSavedKey = !(credential?.key ?? "").isEmpty
    }
}
