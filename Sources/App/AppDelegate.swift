import AppKit
import SwiftUI
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var licenseWindow: NSWindow?
    private let licenseManager = LicenseManager()
    private let screenManager = ScreenManager()
    private var controlsWindow: NSWindow!
    private let panelModel = DlockPanelModel()
    private var isPlacingDock = false
    private var statusRefreshTimer: Timer?
    private var licenseRefreshTimer: Timer?
    private let accessGuide = AccessGuideController()

    private static let showMenuBarIconKey = "showMenuBarIcon"
    private static let useLogoMenuBarIconKey = "useLogoMenuBarIcon"

    private var showMenuBarIcon: Bool {
        get { UserDefaults.standard.object(forKey: Self.showMenuBarIconKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.showMenuBarIconKey) }
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
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            || launchEvent?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue == true
        setupEditingMenu()
        setupStatusItem()
        licenseManager.onAccessChange = { [weak self] unlocked in self?.applyLicenseAccess(unlocked) }
        licenseManager.load()
        UpdateChecker.shared.onStateChange = { [weak self] in
            self?.resizeControlsToFit()
        }
        setupScreenMonitoring()
        licenseRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.licenseManager.refreshIfNeeded() }
        }
        licenseRefreshTimer?.tolerance = 5
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshLicense),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLicense),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        rebuildMenu()
        UpdateChecker.shared.checkSilently()
        if !launchedAtLogin { showControlsWindow() }
        if licenseManager.hasActivation {
            Task {
                await licenseManager.refreshIfNeeded()
                if !licenseManager.isUnlocked {
                    showControlsWindow()
                    showLicense()
                }
            }
        } else {
            showControlsWindow()
            showLicense()
        }
    }

    @objc private func refreshLicense(_ notification: Notification) {
        Task { await licenseManager.refreshIfNeeded() }
    }

    private func setupEditingMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        if mainMenu.items.isEmpty {
            let appItem = NSMenuItem(title: "Dlock", action: nil, keyEquivalent: "")
            let appMenu = NSMenu(title: "Dlock")
            let about = NSMenuItem(title: "About Dlock", action: #selector(showAbout), keyEquivalent: "")
            about.target = self
            appMenu.addItem(about)
            appMenu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit Dlock", action: #selector(quitApp), keyEquivalent: "q")
            quit.target = self
            appMenu.addItem(quit)
            appItem.submenu = appMenu
            mainMenu.addItem(appItem)
        }
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        item.submenu = edit
        mainMenu.addItem(item)
        NSApp.mainMenu = mainMenu
    }

    private func applyLicenseAccess(_ unlocked: Bool) {
        DockGuardian.shared.isProtectionEnabled = unlocked
        if unlocked {
            ensureAccessibilityPermission()
        } else {
            DockGuardian.shared.pause()
            HotkeyManager.shared.unregister()
        }
        rebuildMenu()
    }

    private func ensureAccessibilityPermission() {
        guard licenseManager.isUnlocked else { return }
        if AccessibilityPermission.isGranted() {
            enableAccessibilityFeatures()
            return
        }

        showAccessibilityGuide()
    }

    private func showAccessibilityGuide() {
        controlsWindow?.orderOut(nil)
        accessGuide.show()
        AccessibilityPermission.waitForGrant { [weak self] in
            self?.accessGuide.markGranted()
            self?.enableAccessibilityFeatures()
        }
    }

    private func enableAccessibilityFeatures() {
        guard licenseManager.isUnlocked else { return }
        HotkeyManager.shared.register()
        DockGuardian.shared.refresh()
        Task {
            if UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey) == nil {
                await setLocked(true)
            } else {
                _ = await restorePinnedDock()
            }
            rebuildMenu()
        }
    }

    private func applyDockVisibility() {
        let policy: NSApplication.ActivationPolicy = controlsWindow.isVisible ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlsWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === controlsWindow else { return true }
        hideControlsWindow()
        return false
    }

    private func hideControlsWindow() {
        controlsWindow.orderOut(nil)
        applyDockVisibility()
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
        statusItem.isVisible = showMenuBarIcon
        applyMenuBarIcon()

        let hostingController = NSHostingController(rootView: DlockPanelView(model: panelModel))
        hostingController.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dlock"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: DlockPanelView.width, height: hostingController.view.fittingSize.height))
        window.center()
        controlsWindow = window
        window.delegate = self
        // Poll preferences even with the controls closed. During placement,
        // the guardian must remain paused; its final refresh uses the newest
        // orientation. AX location checks only run while controls are visible.
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isPlacingDock else { return }
            DockGuardian.shared.refreshIfOrientationChanged()
            if self.controlsWindow.isVisible { self.rebuildMenu() }
        }
        statusRefreshTimer?.tolerance = 0.1
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(toggleControlsWindow)
            button.setAccessibilityLabel("Dlock Dock controls")
        }

        panelModel.onAction = { [weak self] action in
            self?.handle(action)
        }

        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            self?.showControlsWindow()
        }
    }

    @objc private func toggleControlsWindow() {
        if controlsWindow.isVisible {
            hideControlsWindow()
        } else {
            showControlsWindow()
        }
    }

    private func showControlsWindow() {
        rebuildMenu()
        controlsWindow.makeKeyAndOrderFront(nil)
        applyDockVisibility()
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow.makeKeyAndOrderFront(nil)
    }

    private func handle(_ action: DlockPanelModel.Action) {
        switch action {
        case .selectDisplay, .setLocked, .setAutohide, .setSizeLock, .setOrientation, .grantAccess, .showProfilesMenu:
            guard licenseManager.isUnlocked else { showLicense(); return }
        default: break
        }
        switch action {
        case .showLicense: showLicense()
        case .selectDisplay(let displayID): Task { await pinToDisplay(displayID) }
        case .setLocked(let locked): Task { await setLocked(locked) }
        case .setAutohide(let enabled): Task { await applyAutohide(enabled) }
        case .setSizeLock(let enabled): Task { await applySizeLock(enabled) }
        case .setOrientation(let orientation): Task { await applyOrientation(orientation) }
        case .grantAccess: openAccessibilitySettings()
        case .showProfilesMenu: showProfilesMenu()
        case .showSettingsMenu: showSettingsMenu()
        case .quit: quitApp()
        }
    }

    // MARK: - Panel menus

    private func showProfilesMenu() {
        guard licenseManager.isUnlocked else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let profiles = panelModel.state.profiles
        if profiles.isEmpty {
            menu.addItem(ActionMenuItem("No Saved Profiles", isEnabled: false) {})
        }
        for profile in profiles {
            let item = ActionMenuItem(profile.name, isChecked: profile.isActive) { [weak self] in
                Task { await self?.activateProfile(id: profile.id) }
            }
            item.toolTip = profile.detail
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Save Current Setup…", isEnabled: panelModel.state.isLocked) { [weak self] in
            self?.promptToSaveProfile()
        })
        if !profiles.isEmpty {
            let delete = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for profile in profiles {
                submenu.addItem(ActionMenuItem(profile.name) { [weak self] in
                    self?.deleteProfile(id: profile.id)
                })
            }
            delete.submenu = submenu
            menu.addItem(delete)
        }
        popUpAtPointer(menu)
    }

    private func showSettingsMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem("License…") { [weak self] in self?.showLicense() })
        menu.addItem(.separator())
        let loginManager = LaunchAtLoginManager.shared
        let loginTitle = loginManager.requiresApproval ? "Launch at Login (Approval Required)" : "Launch at Login"
        menu.addItem(ActionMenuItem(loginTitle, isChecked: loginManager.isEnabled, isEnabled: licenseManager.isUnlocked) { [weak self] in
            self?.toggleLaunchAtLogin()
        })
        if loginManager.requiresApproval {
            menu.addItem(ActionMenuItem("Open Login Items Settings…") {
                SMAppService.openSystemSettingsLoginItems()
            })
        }
        menu.addItem(ActionMenuItem("Show Menu Bar Icon", isChecked: showMenuBarIcon) { [weak self] in
            self?.toggleMenuBarIcon()
        })
        let icon = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")
        let iconMenu = NSMenu()
        iconMenu.addItem(ActionMenuItem("Dlock Logo", isChecked: useLogoMenuBarIcon) { [weak self] in
            self?.selectLogoMenuBarIcon()
        })
        iconMenu.addItem(ActionMenuItem("Dock Symbol", isChecked: !useLogoMenuBarIcon) { [weak self] in
            self?.selectDefaultMenuBarIcon()
        })
        icon.submenu = iconMenu
        menu.addItem(icon)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Open Display Settings…") {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
            NSWorkspace.shared.open(url)
        })
        menu.addItem(ActionMenuItem("Move Dock to Main Display", isEnabled: licenseManager.isUnlocked && AccessibilityPermission.isGranted()) { [weak self] in
            Task { await self?.resetToMainDisplay() }
        })
        menu.addItem(ActionMenuItem("Check for Updates…", isEnabled: UpdateChecker.shared.state != .checking) { [weak self] in self?.checkForUpdates() })
        menu.addItem(ActionMenuItem("About Dlock") { [weak self] in self?.showAbout() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Hold ⌥ to let the Dock move · ⌘⌃⌥D opens Dlock", isEnabled: false) {})
        popUpAtPointer(menu)
    }

    private func popUpAtPointer(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func setupScreenMonitoring() {
        screenManager.onScreenParametersChanged = { [weak self] in
            self?.rebuildMenu()
        }
        screenManager.onScreenDisconnected = { [weak self] name in
            guard self?.licenseManager.isUnlocked == true else { return }
            NotificationManager.shared.screenDisconnected(name: name)
        }
        screenManager.onScreenReconnected = { [weak self] screen in
            Task { [weak self] in
                guard let self, self.licenseManager.isUnlocked else { return }
                _ = await self.restorePinnedDock()
                guard self.screenManager.pinnedScreen?.displayID == screen.displayID else { return }
                let restored = DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID
                NotificationManager.shared.screenReconnected(name: screen.localizedName, restored: restored)
                self.rebuildMenu()
            }
        }
        screenManager.startMonitoring()
    }

    private func rebuildMenu() {
        statusItem.menu = nil
        let screens = NSScreen.screens
        let pinnedID = UserDefaults.standard.string(forKey: ScreenManager.pinnedScreenKey)
        let pinnedScreen = pinnedID.flatMap(NSScreen.screen(matching:))
        let isGranted = AccessibilityPermission.isGranted()
        let orientation = DockController.shared.getOrientation()
        let autohide = DockController.shared.readAutohide()

        let dockScreen = isGranted ? DockGuardian.shared.currentDockScreen() : nil
        let status = DlockPanelModel.resolveLockStatus(
            hasAccess: isGranted,
            pinnedDisplayID: licenseManager.isUnlocked ? (pinnedScreen?.displayID ?? pinnedID) : nil,
            dockDisplayID: dockScreen?.displayID,
            connectedDisplayIDs: screens.map(\.displayID),
            guardActive: DockGuardian.shared.isGuardActive)
        let title: String
        let detail: String
        switch status {
        case .needsAccess:
            title = "Accessibility access needed"
            detail = "Dlock needs it to stop the Dock from following your pointer."
        case .locked:
            title = "Locked to \(pinnedScreen?.localizedName ?? "your display")"
            detail = "Dock location confirmed. Protecting its edge on other displays."
        case .unlocked:
            title = "Dock not locked"
            detail = "The Dock follows the pointer."
        case .singleDisplay:
            title = "Single display"
            detail = "Connect another display to use Dock Lock."
        case .attention:
            if pinnedScreen == nil {
                title = "Selected display disconnected"
                detail = "Selected display disconnected\nReconnect it or choose another"
            } else if !DockGuardian.shared.isGuardActive {
                title = "Dock protection is inactive"
                detail = "Dock protection is inactive\nReopen Dlock or contact support"
            } else if dockScreen == nil {
                title = "Can’t verify Dock location"
                detail = "Can’t verify Dock location\nSelect your display to retry"
            } else {
                title = "Dock is on another screen"
                detail = "Dock is on another screen\nSelect your display to retry"
            }
        }

        let profiles = ProfileManager.shared.profiles.map { profile in
            let screenName = NSScreen.screen(matching: profile.displayID)?.localizedName
                ?? profile.displayName ?? "Disconnected display"
            let detail = [screenName, profile.autohide ? "Auto-hide" : nil]
                .compactMap { $0 }
                .joined(separator: " · ")
            let isActive = pinnedScreen.map { NSScreen.screen(matching: profile.displayID) == $0 } == true
                && profile.autohide == (autohide ?? false)
            return DlockPanelModel.Profile(id: profile.id, name: profile.name, detail: detail, isActive: isActive)
        }

        let nextState = DlockPanelModel.State(
            isLicensed: licenseManager.isUnlocked,
            displays: screens.enumerated().map { index, screen in
                .init(
                    id: screen.displayID,
                    name: screen.localizedName,
                    frame: screen.frame,
                    isMain: index == 0,
                    isBuiltIn: screen.directDisplayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
                )
            },
            pinnedDisplayID: licenseManager.isUnlocked ? (pinnedScreen?.displayID ?? pinnedID) : nil,
            dockDisplayID: dockScreen?.displayID,
            orientation: orientation,
            autohideEnabled: autohide,
            sizeLockEnabled: DockController.shared.readSizeLock(),
            displaysHaveSeparateSpaces: NSScreen.screensHaveSeparateSpaces,
            status: status,
            statusTitle: title,
            statusDetail: detail,
            profiles: profiles
        )
        if panelModel.state != nextState {
            let layoutChanged = panelModel.state.orientation != nextState.orientation
                || panelModel.state.displays != nextState.displays
                || panelModel.state.displaysHaveSeparateSpaces != nextState.displaysHaveSeparateSpaces
            panelModel.state = nextState
            if layoutChanged {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let content = self.controlsWindow.contentView else { return }
                    content.layoutSubtreeIfNeeded()
                    self.controlsWindow.setContentSize(NSSize(width: DlockPanelView.width, height: content.fittingSize.height))
                }
            }
        }
    }

    // MARK: - Actions

    private func setLocked(_ locked: Bool) async {
        guard licenseManager.isUnlocked else { return }
        guard !isPlacingDock else { return }
        if locked {
            guard let screen = DockGuardian.shared.currentDockScreen() ?? NSScreen.screens.first else { return }
            await pinToDisplay(screen.displayID)
        } else {
            screenManager.resetPin()
            panelModel.flash("Dock unlocked. It follows the pointer again.")
            rebuildMenu()
        }
    }

    private func promptToSaveProfile() {
        guard licenseManager.isUnlocked else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Save Profile"
        alert.informativeText = "Saves the locked display and auto-hide setting."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        textField.placeholderString = "Profile name"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        saveProfile(named: name)
    }

    private func pinToDisplay(_ displayID: String) async {
        guard licenseManager.isUnlocked else { return }
        guard !isPlacingDock else { return }
        guard let screen = NSScreen.screen(matching: displayID), await placeDock(on: screen) else {
            rebuildMenu()
            return
        }
        guard licenseManager.isUnlocked else { return }
        screenManager.pin(to: screen)
        panelModel.flash("Dock locked to \(screen.localizedName).")
        rebuildMenu()
    }

    private func applyOrientation(_ orientation: DockOrientation) async {
        guard licenseManager.isUnlocked else { return }
        licenseManager.isFeatureOperationInProgress = true
        defer { licenseManager.isFeatureOperationInProgress = false }
        guard !isPlacingDock else { return }
        guard AccessibilityPermission.isGranted() else {
            showAccessibilityGuide()
            return
        }
        guard DockController.shared.readOrientation() != orientation else { rebuildMenu(); return }
        let result: DockController.ChangeResult
        do {
            isPlacingDock = true
            DockGuardian.shared.pause()
            defer {
                isPlacingDock = false
                DockGuardian.shared.refresh()
            }
            result = DockController.shared.changeOrientation(to: orientation)
        }
        switch result {
        case .applied:
            if orientation == .bottom {
                if await restorePinnedDock() {
                    panelModel.flash("Dock position is now Bottom.")
                }
            } else {
                panelModel.flash("Dock position is now \(orientation.displayName). macOS controls which display uses this edge.")
            }
        case .notSaved:
            panelModel.flash("macOS could not save \(orientation.displayName). Try again or change Dock position in System Settings.", isError: true)
        case .savedWithoutRestart:
            panelModel.flash("\(orientation.displayName) is saved, but the Dock did not restart. Apply it in System Settings.", isError: true)
        }
        rebuildMenu()
    }

    private func applySizeLock(_ enabled: Bool) async {
        guard licenseManager.isUnlocked, !isPlacingDock else { return }
        guard AccessibilityPermission.isGranted() else { showAccessibilityGuide(); return }
        licenseManager.isFeatureOperationInProgress = true
        DockGuardian.shared.pause()
        defer {
            licenseManager.isFeatureOperationInProgress = false
            DockGuardian.shared.refresh()
            rebuildMenu()
        }
        isPlacingDock = true
        let result = DockController.shared.changeSizeLock(to: enabled)
        isPlacingDock = false
        switch result {
        case .applied:
            guard await restorePinnedDock() else { return }
            panelModel.flash(enabled ? "Dock size is locked." : "Dock size is unlocked.")
        case .notSaved:
            panelModel.flash("macOS could not save the Dock size lock. Try again.", isError: true)
        case .savedWithoutRestart:
            panelModel.flash("Size lock is saved, but the Dock did not restart. The change is not confirmed yet.", isError: true)
        }
    }

    private func applyAutohide(_ enabled: Bool) async {
        guard licenseManager.isUnlocked else { return }
        licenseManager.isFeatureOperationInProgress = true
        defer { licenseManager.isFeatureOperationInProgress = false }
        guard !isPlacingDock else { return }
        DockGuardian.shared.pause()
        let result = DockController.shared.changeAutohide(to: enabled)
        let restored = await restorePinnedDock()
        DockGuardian.shared.refresh()
        guard restored else { rebuildMenu(); return }

        let state = enabled ? "On" : "Off"
        switch result {
        case .applied:
            panelModel.flash("Auto-hide is now \(state).")
        case .savedWithoutRestart:
            panelModel.flash("Auto-hide is saved as \(state), but the Dock did not restart. Reopen Dlock to refresh it.", isError: true)
        case .notSaved:
            panelModel.flash("macOS did not save Auto-hide \(state). Try again.", isError: true)
        }
        rebuildMenu()
    }

    private func activateProfile(id profileID: UUID) async {
        guard licenseManager.isUnlocked else { return }
        licenseManager.isFeatureOperationInProgress = true
        defer { licenseManager.isFeatureOperationInProgress = false }
        guard !isPlacingDock else { return }
        guard let profile = ProfileManager.shared.profiles.first(where: { $0.id == profileID }) else { return }
        guard let targetScreen = NSScreen.screen(matching: profile.displayID) else {
            showAlert(
                title: "Profile Screen Is Not Connected",
                message: "Connect \(profile.displayName ?? "the profile's display") and try again."
            )
            return
        }

        DockGuardian.shared.pause()
        // Position is managed by macOS for this build, including old profiles.
        guard DockController.shared.changeAutohide(to: profile.autohide) == .applied else {
            panelModel.flash("Could not apply Auto-hide from \(profile.name).", isError: true)
            DockGuardian.shared.refresh()
            rebuildMenu()
            return
        }
        guard await placeDock(on: targetScreen) else {
            DockGuardian.shared.refresh()
            return
        }
        screenManager.activateProfile(profile, on: targetScreen)
        NotificationManager.shared.profileActivated(name: profile.name)
        panelModel.flash("Applied \(profile.name).")
        rebuildMenu()
    }


    private func saveProfile(named name: String) {
        guard licenseManager.isUnlocked else { return }
        guard ProfileManager.shared.saveCurrentAsProfile(name: name) != nil else {
            panelModel.flash("Lock the Dock to a display before saving a profile.", isError: true)
            return
        }
        panelModel.flash("Saved profile \(name).")
        rebuildMenu()
    }

    private func deleteProfile(id: UUID) {
        guard licenseManager.isUnlocked else { return }
        guard let profile = ProfileManager.shared.profiles.first(where: { $0.id == id }) else { return }
        ProfileManager.shared.deleteProfile(id: id)
        panelModel.flash("Deleted \(profile.name).")
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        guard licenseManager.isUnlocked else { return }
        switch LaunchAtLoginManager.shared.toggle() {
        case .enabled:
            panelModel.flash("Launch at Login is enabled.")
        case .disabled:
            panelModel.flash("Launch at Login is disabled.")
        case .requiresApproval:
            panelModel.flash("Approve Dlock in System Settings → General → Login Items. Open Login Items Settings from Dlock’s Settings menu.", isError: true)
        case .unavailable:
            panelModel.flash("macOS could not find Dlock’s login item. Keep Dlock in Applications and try again.", isError: true)
        case .failed(let message):
            panelModel.flash("Could not change Launch at Login: \(message)", isError: true)
        }
        rebuildMenu()
    }

    @objc private func toggleMenuBarIcon() {
        showMenuBarIcon.toggle()
        statusItem.isVisible = showMenuBarIcon
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

    @objc private func resetToMainDisplay() async {
        guard !isPlacingDock else { return }
        guard let primaryScreen = NSScreen.screens.first,
              await placeDock(on: primaryScreen) else { return }
        screenManager.resetPin()
        panelModel.flash("Dock unlocked and back on \(primaryScreen.localizedName).")
        rebuildMenu()
    }

    @objc private func checkForUpdates() {
        showControlsWindow()
        UpdateChecker.shared.check()
    }

    private func resizeControlsToFit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let content = self.controlsWindow?.contentView else { return }
            content.layoutSubtreeIfNeeded()
            self.controlsWindow.setContentSize(NSSize(width: DlockPanelView.width, height: content.fittingSize.height))
        }
    }

    @objc private func openAccessibilitySettings() {
        guard !AccessibilityPermission.isGranted() else { return }
        showAccessibilityGuide()
    }

    private func showLicense() {
        licenseManager.load()
        if licenseWindow == nil {
            let controller = NSHostingController(rootView: LicenseView(manager: licenseManager))
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Dlock License — Testing"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: controlsWindow.level.rawValue + 1)
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            licenseWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        licenseWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let credits = NSMutableAttributedString(string: "Your Dock. Locked to your preferred screen.\n", attributes: attributes)
        credits.addAttribute(.font, value: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold), range: NSRange(location: 0, length: credits.length))
        credits.append(NSAttributedString(
            string: "\nCreated by Kevin Mukoond • 🇲🇺\n\n",
            attributes: attributes
        ))
        let links = [
            ("Website", "https://kevin.mu"),
            ("𝕏", "https://x.com/mkev07"),
            ("Report an Issue", "mailto:reachme@kevin.mu")
        ]
        for (index, link) in links.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: " • ", attributes: attributes)) }
            var linkAttributes = attributes
            linkAttributes[.link] = URL(string: link.1)!
            credits.append(NSAttributedString(string: link.0, attributes: linkAttributes))
        }
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Dlock",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            .version: "",
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "",
            .credits: credits
        ])
        for window in NSApp.windows {
            if let content = window.contentView, configureAboutTooltip(in: content) {
                window.level = NSWindow.Level(rawValue: controlsWindow.level.rawValue + 1)
                window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func configureAboutTooltip(in view: NSView) -> Bool {
        if let textView = view as? NSTextView,
           textView.string.contains("Created by Kevin Mukoond • 🇲🇺") {
            AboutFlagTooltip.install(in: textView)
            return true
        }
        return view.subviews.contains { configureAboutTooltip(in: $0) }
    }

    @objc private func quitApp() {
        DockGuardian.shared.pause()
        HotkeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    private func restorePinnedDock() async -> Bool {
        guard let screen = screenManager.pinnedScreen else { return true }
        return await placeDock(on: screen)
    }

    private func placeDock(on screen: NSScreen) async -> Bool {
        guard licenseManager.isUnlocked else { return false }
        licenseManager.isFeatureOperationInProgress = true
        defer { licenseManager.isFeatureOperationInProgress = false }
        guard !isPlacingDock else { return false }
        if DockGuardian.shared.currentDockScreen()?.displayID == screen.displayID { return true }
        // Both apps install input guards around Dock edges. A competing guard
        // can intercept our placement gesture before it reaches the Dock.
        if let competingApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "pro.docklock.lite").first {
            panelModel.flash("Quit \(competingApp.localizedName ?? "DockLock Lite") before moving the Dock with Dlock.", isError: true)
            return false
        }
        guard AccessibilityPermission.isGranted() else {
            showAccessibilityGuide()
            return false
        }
        if DockController.shared.getOrientation() == .bottom,
           let displayID = screen.directDisplayID,
           DockLayoutGeometry.placementPoint(in: CGDisplayBounds(displayID), orientation: .bottom,
               displays: NSScreen.screens.compactMap { $0.directDisplayID.map(CGDisplayBounds) }) == nil {
            panelModel.layoutHelpDisplayID = screen.displayID
            panelModel.flash("The bottom edge of \(screen.localizedName) is covered. Open the layout tip above Displays to see how to arrange it.", isError: true)
            return false
        }
        isPlacingDock = true
        DockGuardian.shared.pause()
        defer {
            isPlacingDock = false
            DockGuardian.shared.refresh()
        }
        let moved = await DockController.shared.moveDock(to: screen)
        if !moved {
            panelModel.flash("macOS could not move the Dock to \(screen.localizedName). Check the display arrangement and try again.", isError: true)
        }
        return moved
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

/// NSMenuItem that runs a closure, for menus built on the fly.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, isChecked: Bool = false, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = isChecked ? .on : .off
        self.isEnabled = isEnabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        handler()
    }
}
