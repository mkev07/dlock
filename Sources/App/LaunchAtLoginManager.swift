import Foundation
import ServiceManagement

class LaunchAtLoginManager {

    static let shared = LaunchAtLoginManager()
    private let key = "launchAtLogin"

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func toggle() {
        isEnabled = !isEnabled
        apply()
    }

    func apply() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if isEnabled {
                do {
                    try service.register()
                } catch {
                    print("DLock: failed to register for login item: \(error)")
                }
            } else {
                do {
                    try service.unregister()
                } catch {
                    print("DLock: failed to unregister login item: \(error)")
                }
            }
        }
    }
}
