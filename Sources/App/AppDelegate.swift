import AppKit
import PermissionFlow

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let screenManager = ScreenManager()
    private lazy var permissionFlowController = PermissionFlow.makeController(
        configuration: PermissionFlowConfiguration(promptForAccessibilityTrust: false)
    )

    private static let showInDockKey = "showInDock"
    private static let useLogoMenuBarIconKey = "useLogoMenuBarIcon"

    private var showInDock: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showInDockKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showInDockKey) }
    }

    private var useLogoMenuBarIcon: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.useLogoMenuBarIconKey) != nil else {
                return true // default to logo
            }
            return UserDefaults.standard.bool(forKey: Self.useLogoMenuBarIconKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.useLogoMenuBarIconKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockVisibility()
        setupStatusItem()
        setupScreenMonitoring()
        rebuildMenu()
        UpdateChecker.shared.checkSilently()
        ensureAccessibilityPermission()
    }

    private func ensureAccessibilityPermission() {
        if AccessibilityPermission.isGranted() {
            enableAccessibilityFeatures()
            return
        }

        showAccessibilityGuide()
        AccessibilityPermission.waitForGrant { [weak self] in
            self?.permissionFlowController.closePanel()
            self?.enableAccessibilityFeatures()
        }
    }

    @MainActor
    private func showAccessibilityGuide() {
        permissionFlowController.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL]
        )
    }

    private func enableAccessibilityFeatures() {
        HotkeyManager.shared.register()
        DockGuardian.shared.refresh()
        rebuildMenu()
    }

    private func applyDockVisibility() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    private func applyMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let image: NSImage?
        if useLogoMenuBarIcon {
            image = NSImage(named: "menubar_logo")
                ?? NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled", accessibilityDescription: "Dlock")
        } else {
            image = NSImage(named: "menubar_icon")
                ?? NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled", accessibilityDescription: "Dlock")
        }
        image?.isTemplate = true
        button.image = image
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyMenuBarIcon()
        updateButtonTitle(nil)

        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            guard let button = self?.statusItem.button else { return }
            self?.statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: self!.buttonHeight()), in: button)
        }
    }

    private func buttonHeight() -> CGFloat {
        return statusItem.button?.frame.height ?? 22
    }

    private func updateButtonTitle(_ screenName: String?) {
        guard let button = statusItem.button else { return }
        button.title = ""
    }

    private func setupScreenMonitoring() {
        screenManager.onScreenParametersChanged = { [weak self] in
            self?.rebuildMenu()
        }
        screenManager.onScreenDisconnected = { [weak self] name in
            self?.updateButtonTitle(nil)
            NotificationManager.shared.screenDisconnected(name: name)
        }
        screenManager.onScreenReconnected = { [weak self] screen in
            NotificationManager.shared.screenReconnected(name: screen.localizedName)
            self?.rebuildMenu()
        }
        screenManager.startMonitoring()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Current state
        let pinnedName = screenManager.pinnedScreenName ?? "None"
        let stateSuffix: String
        if screenManager.pinnedScreenName != nil && !screenManager.isPinnedScreenConnected {
            stateSuffix = " (disconnected)"
        } else if let pinnedScreen = screenManager.pinnedScreen,
                  DockGuardian.shared.currentDockScreen()?.displayID != pinnedScreen.displayID {
            stateSuffix = " — move Dock here once"
        } else {
            stateSuffix = ""
        }
        let stateLabel = NSMenuItem(title: "Pinned: \(pinnedName)\(stateSuffix)", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        menu.addItem(NSMenuItem.separator())

        // Screens submenu
        let screensMenu = NSMenu()
        let screensItem = NSMenuItem(title: "Pin to Screen", action: nil, keyEquivalent: "")
        let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey)

        for screen in NSScreen.screens {
            let displayID = screen.displayID
            let item = NSMenuItem(
                title: screen.localizedName,
                action: #selector(pinToScreen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = displayID
            item.state = (displayID == pinnedID) ? .on : .off
            screensMenu.addItem(item)
        }
        screensItem.submenu = screensMenu
        menu.addItem(screensItem)

        let bypassItem = NSMenuItem(
            title: "Hold ⌥ Option to move the Dock temporarily",
            action: nil,
            keyEquivalent: ""
        )
        bypassItem.isEnabled = false
        menu.addItem(bypassItem)

        menu.addItem(NSMenuItem.separator())

        // Orientation
        let orientMenu = NSMenu()
        let orientItem = NSMenuItem(title: "Orientation", action: nil, keyEquivalent: "")
        for orient in DockOrientation.allCases {
            let item = NSMenuItem(
                title: orient.displayName,
                action: #selector(setOrientation(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = orient
            item.state = DockController.shared.getOrientation() == orient ? .on : .off
            orientMenu.addItem(item)
        }
        orientItem.submenu = orientMenu
        menu.addItem(orientItem)

        // Auto-hide
        let autoItem = NSMenuItem(
            title: "Auto-hide Dock",
            action: #selector(toggleAutohide),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = DockController.shared.getAutohide() ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(NSMenuItem.separator())

        // Profiles submenu
        let profilesMenu = NSMenu()
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profiles = ProfileManager.shared.profiles
        for profile in profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(activateProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = profile.id
            profilesMenu.addItem(item)
        }

        if !profiles.isEmpty {
            profilesMenu.addItem(NSMenuItem.separator())
        }

        let saveItem = NSMenuItem(title: "Save Current as Profile...", action: #selector(saveProfile), keyEquivalent: "")
        saveItem.target = self
        profilesMenu.addItem(saveItem)

        if !profiles.isEmpty {
            profilesMenu.addItem(NSMenuItem.separator())
            let deleteItem = NSMenuItem(title: "Delete Profile...", action: #selector(deleteProfile), keyEquivalent: "")
            deleteItem.target = self
            profilesMenu.addItem(deleteItem)
        }

        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at login
        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(launchItem)

        // Menu bar icon style
        let iconStyleMenu = NSMenu()
        let iconStyleItem = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")

        let defaultIconItem = NSMenuItem(title: "Default", action: #selector(selectDefaultMenuBarIcon), keyEquivalent: "")
        defaultIconItem.target = self
        defaultIconItem.state = useLogoMenuBarIcon ? .off : .on
        iconStyleMenu.addItem(defaultIconItem)

        let logoIconItem = NSMenuItem(title: "App Logo", action: #selector(selectLogoMenuBarIcon), keyEquivalent: "")
        logoIconItem.target = self
        logoIconItem.state = useLogoMenuBarIcon ? .on : .off
        iconStyleMenu.addItem(logoIconItem)

        iconStyleItem.submenu = iconStyleMenu
        menu.addItem(iconStyleItem)

        // Show in Dock
        let dockItem = NSMenuItem(
            title: "Show in Dock",
            action: #selector(toggleShowInDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        dockItem.state = showInDock ? .on : .off
        menu.addItem(dockItem)

        // Accessibility status
        let axGranted = AccessibilityPermission.isGranted()
        let axItem = NSMenuItem(
            title: axGranted ? "Accessibility: Granted" : "Grant Accessibility Access...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        axItem.target = self
        if axGranted { axItem.state = .on }
        menu.addItem(axItem)

        // Check for Updates
        let updatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About Dlock",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Reset
        let resetItem = NSMenuItem(
            title: "Reset to Main Display",
            action: #selector(resetToMainDisplay),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Dlock",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func pinToScreen(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? String,
              let screen = NSScreen.screen(matching: displayID),
              placeDock(on: screen) else { return }
        screenManager.pin(to: screen)
        updateButtonTitle(screenManager.pinnedScreenName)
        rebuildMenu()
    }

    @objc private func setOrientation(_ sender: NSMenuItem) {
        guard let orient = sender.representedObject as? DockOrientation else { return }
        DockGuardian.shared.pause()
        DockController.shared.setOrientation(orient)
        DockController.shared.restartDock()
        if let pinnedScreen = screenManager.pinnedScreen {
            _ = placeDock(on: pinnedScreen)
        }
        DockGuardian.shared.refresh()
        rebuildMenu()
    }

    @objc private func toggleAutohide() {
        let current = DockController.shared.getAutohide()
        DockGuardian.shared.pause()
        DockController.shared.setAutohide(!current)
        DockController.shared.restartDock()
        if let pinnedScreen = screenManager.pinnedScreen {
            _ = placeDock(on: pinnedScreen)
        }
        DockGuardian.shared.refresh()
        rebuildMenu()
    }

    @objc private func activateProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? UUID,
              let profile = ProfileManager.shared.profiles.first(where: { $0.id == profileID }) else { return }
        guard let targetScreen = NSScreen.screen(matching: profile.displayID) else {
            showAlert(
                title: "Profile Screen Is Not Connected",
                message: "Connect \(profile.displayName ?? "the profile's display") and try again."
            )
            return
        }

        DockGuardian.shared.pause()
        DockController.shared.applySettings(profile: profile)
        guard placeDock(on: targetScreen) else {
            DockGuardian.shared.refresh()
            return
        }
        screenManager.activateProfile(profile, on: targetScreen)
        NotificationManager.shared.profileActivated(name: profile.name)
        rebuildMenu()
    }

    @objc private func saveProfile() {
        guard screenManager.pinnedScreenName != nil else {
            let alert = NSAlert()
            alert.messageText = "No Screen Pinned"
            alert.informativeText = "Pin a screen first before saving a profile."
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save Profile"
        alert.informativeText = "Enter a name for this profile:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "Profile name"
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                _ = ProfileManager.shared.saveCurrentAsProfile(name: name)
                rebuildMenu()
            }
        }
    }

    @objc private func deleteProfile() {
        let profiles = ProfileManager.shared.profiles
        guard !profiles.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Profile"
        alert.informativeText = "Select a profile to delete:"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        for profile in profiles {
            popup.addItem(withTitle: profile.name)
            popup.lastItem?.representedObject = profile.id
        }
        alert.accessoryView = popup

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let selectedID = popup.selectedItem?.representedObject as? UUID {
                ProfileManager.shared.deleteProfile(id: selectedID)
                rebuildMenu()
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.shared.toggle()
        rebuildMenu()
    }

    @objc private func toggleShowInDock() {
        showInDock = !showInDock
        applyDockVisibility()
        rebuildMenu()
    }

    @objc private func selectDefaultMenuBarIcon() {
        useLogoMenuBarIcon = false
        applyMenuBarIcon()
        rebuildMenu()
    }

    @objc private func selectLogoMenuBarIcon() {
        useLogoMenuBarIcon = true
        applyMenuBarIcon()
        rebuildMenu()
    }

    @objc private func resetToMainDisplay() {
        guard let primaryScreen = NSScreen.screens.first,
              placeDock(on: primaryScreen) else { return }
        screenManager.resetPin()
        updateButtonTitle(nil)
        rebuildMenu()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkAndNotify()
    }

    @objc private func openAccessibilitySettings() {
        guard !AccessibilityPermission.isGranted() else { return }
        showAccessibilityGuide()
        // If the user grants it after returning, pick it up automatically.
        AccessibilityPermission.waitForGrant { [weak self] in
            self?.permissionFlowController.closePanel()
            self?.enableAccessibilityFeatures()
        }
    }

    @objc private func showAbout() {
        // Use NSApp's About panel which automatically uses the app icon
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Dlock",
            .applicationVersion: "1.0.0",
            .version: "1.0.0",
            .credits: NSAttributedString(
                string: "A macOS menu bar app that prevents the Dock from following the pointer away from your preferred screen.\n\nBuilt with Swift and AppKit.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
            )
        ])
    }

    @objc private func quitApp() {
        DockGuardian.shared.pause()
        HotkeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    private func placeDock(on screen: NSScreen) -> Bool {
        if DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID {
            return true
        }

        guard AccessibilityPermission.isGranted() else {
            showAlert(
                title: "Accessibility Permission Required",
                message: "Grant Accessibility access before choosing a pinned display."
            )
            AccessibilityPermission.openSettings()
            return false
        }

        DockGuardian.shared.pause()
        let edge = DockController.shared.getOrientation().displayName.lowercased()
        let alert = NSAlert()
        alert.messageText = "Move the Dock to \(screen.localizedName)"
        alert.informativeText = "Move the pointer onto \(screen.localizedName), then push it against the \(edge) edge until the Dock appears there. Click Verify when it is in place."
        alert.addButton(withTitle: "Verify")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            DockGuardian.shared.refresh()
            return false
        }

        guard DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID else {
            showAlert(
                title: "Dock Not Detected on \(screen.localizedName)",
                message: "The Dock did not move. Try again and keep pushing against the \(edge) edge until it appears before clicking Verify."
            )
            DockGuardian.shared.refresh()
            return false
        }
        return true
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
