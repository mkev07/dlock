import Foundation
import ServiceManagement

class LaunchAtLoginManager {

    static let shared = LaunchAtLoginManager()

    enum ChangeResult: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
        case failed(String)
    }

    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
    }

    var status: SMAppService.Status { readStatus() }
    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func toggle() -> ChangeResult {
        let currentStatus = status
        do {
            if currentStatus == .enabled || currentStatus == .requiresApproval {
                try unregister()
            } else {
                try register()
            }
        } catch {
            return .failed(error.localizedDescription)
        }
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
}
