import AppKit
import ColorSync
import CoreGraphics

final class ScreenManager {

    static let pinnedScreenKey = "pinnedScreenDisplayID"
    static let pinnedScreenNameKey = "pinnedScreenName"

    var onScreenParametersChanged: (() -> Void)?
    var onScreenDisconnected: ((String) -> Void)?
    var onScreenReconnected: ((NSScreen) -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var pinnedScreenUnavailable = false

    var pinnedScreen: NSScreen? {
        guard let pinnedID = UserDefaults.standard.string(forKey: Self.pinnedScreenKey),
              let screen = NSScreen.screen(matching: pinnedID) else { return nil }
        migrateStoredIdentityIfNeeded(screen: screen, storedID: pinnedID)
        return screen
    }

    var pinnedScreenName: String? {
        pinnedScreen?.localizedName
            ?? UserDefaults.standard.string(forKey: Self.pinnedScreenNameKey)
    }

    var isPinnedScreenConnected: Bool {
        pinnedScreen != nil
    }

    func startMonitoring() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPinnedScreen()
            self?.onScreenParametersChanged?()
        }
        checkPinnedScreen()
    }

    func stopMonitoring() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    func pin(to screen: NSScreen) {
        storePin(for: screen)
        pinnedScreenUnavailable = false
        DockGuardian.shared.refresh()
    }

    func activateProfile(_ profile: DLockProfile, on screen: NSScreen) {
        var migratedProfile = profile
        migratedProfile.displayID = screen.displayID
        migratedProfile.displayName = screen.localizedName
        if migratedProfile.displayID != profile.displayID || migratedProfile.displayName != profile.displayName {
            ProfileManager.shared.updateProfile(migratedProfile)
        }

        storePin(for: screen)
        pinnedScreenUnavailable = false
        DockGuardian.shared.refresh()
    }

    func resetPin() {
        UserDefaults.standard.removeObject(forKey: Self.pinnedScreenKey)
        UserDefaults.standard.removeObject(forKey: Self.pinnedScreenNameKey)
        pinnedScreenUnavailable = false
        DockGuardian.shared.refresh()
    }

    private func checkPinnedScreen() {
        guard UserDefaults.standard.string(forKey: Self.pinnedScreenKey) != nil else {
            pinnedScreenUnavailable = false
            DockGuardian.shared.refresh()
            return
        }

        if let screen = pinnedScreen {
            let reconnected = pinnedScreenUnavailable
            pinnedScreenUnavailable = false
            DockGuardian.shared.refresh()
            if reconnected {
                onScreenReconnected?(screen)
            }
            return
        }

        guard !pinnedScreenUnavailable else { return }
        pinnedScreenUnavailable = true
        onScreenDisconnected?(pinnedScreenName ?? "Pinned screen")
        DockGuardian.shared.refresh()
    }

    private func storePin(for screen: NSScreen) {
        UserDefaults.standard.set(screen.displayID, forKey: Self.pinnedScreenKey)
        UserDefaults.standard.set(screen.localizedName, forKey: Self.pinnedScreenNameKey)
    }

    private func migrateStoredIdentityIfNeeded(screen: NSScreen, storedID: String) {
        guard storedID != screen.displayID else { return }
        storePin(for: screen)
    }
}

extension NSScreen {
    var directDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var displayID: String {
        guard let directDisplayID else {
            return "display:v1:name:\(localizedName)"
        }
        let uuid = CGDisplayCreateUUIDFromDisplayID(directDisplayID).takeRetainedValue()
        return "display:v2:\(CFUUIDCreateString(nil, uuid) as String)"
    }

    private var legacyDisplayID: String? {
        directDisplayID.map(String.init)
    }

    private var legacyFingerprint: String? {
        guard let directDisplayID else { return nil }
        let vendor = CGDisplayVendorNumber(directDisplayID)
        let model = CGDisplayModelNumber(directDisplayID)
        let serial = CGDisplaySerialNumber(directDisplayID)
        let size = CGDisplayScreenSize(directDisplayID)
        return "display:v1:\(vendor):\(model):\(serial):\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    static func screen(matching storedID: String) -> NSScreen? {
        screens.first { screen in
            screen.displayID == storedID
                || screen.legacyDisplayID == storedID
                || screen.legacyFingerprint == storedID
        }
    }
}
