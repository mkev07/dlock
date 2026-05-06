import Foundation
import AppKit

class ProfileManager {

    static let shared = ProfileManager()
    private let profilesKey = "dlockProfiles"

    private init() {}

    var profiles: [DLockProfile] {
        get {
            guard let data = UserDefaults.standard.data(forKey: profilesKey) else { return [] }
            return (try? JSONDecoder().decode([DLockProfile].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: profilesKey)
            }
        }
    }

    func addProfile(_ profile: DLockProfile) {
        var current = profiles
        current.append(profile)
        profiles = current
    }

    func updateProfile(_ profile: DLockProfile) {
        var current = profiles
        if let idx = current.firstIndex(where: { $0.id == profile.id }) {
            current[idx] = profile
            profiles = current
        }
    }

    func deleteProfile(id: UUID) {
        var current = profiles
        current.removeAll { $0.id == id }
        profiles = current
    }

    func saveCurrentAsProfile(name: String) -> DLockProfile? {
        guard let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey) else { return nil }

        let profile = DLockProfile(
            name: name,
            displayID: pinnedID,
            orientation: DockController.shared.getOrientation(),
            autohide: DockController.shared.getAutohide()
        )
        addProfile(profile)
        return profile
    }
}
