import AppKit

class ScreenManager {

    static let pinnedScreenKey = "pinnedScreenDisplayID"

    var onScreenParametersChanged: (() -> Void)?
    var onScreenDisconnected: ((String) -> Void)?
    private var workspaceObserver: NSObjectProtocol?

    var pinnedScreenName: String? {
        guard let pinnedID = UserDefaults.standard.string(forKey: Self.pinnedScreenKey) else { return nil }
        return NSScreen.screens.first { $0.displayID == pinnedID }?.localizedName
    }

    var pinnedScreenKey: String {
        return Self.pinnedScreenKey
    }

    func startMonitoring() {
        workspaceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPinnedScreen()
            self?.onScreenParametersChanged?()
        }
    }

    func stopMonitoring() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func checkPinnedScreen() {
        guard let pinnedID = UserDefaults.standard.string(forKey: Self.pinnedScreenKey) else { return }
        let currentScreens = NSScreen.screens
        let pinnedExists = currentScreens.contains { $0.displayID == pinnedID }

        if !pinnedExists {
            let screenName = pinnedScreenName ?? "Pinned screen"
            onScreenDisconnected?(screenName)
            resetToMainDisplay()
        }
    }

    func pinToDisplayID(_ displayID: String) {
        let screens = NSScreen.screens
        guard let targetScreen = screens.first(where: { $0.displayID == displayID }) else { return }

        UserDefaults.standard.set(displayID, forKey: Self.pinnedScreenKey)
        DockController.shared.moveDockToScreen(targetScreen)
    }

    func resetToMainDisplay() {
        UserDefaults.standard.removeObject(forKey: Self.pinnedScreenKey)
        if let mainScreen = NSScreen.main {
            DockController.shared.moveDockToScreen(mainScreen)
        }
    }
}

extension NSScreen {
    var displayID: String {
        let info = deviceDescription
        if let screenNumber = info[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return String(screenNumber)
        }
        return String(ObjectIdentifier(self).hashValue)
    }
}
