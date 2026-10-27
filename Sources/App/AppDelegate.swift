import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var diagnosticsWindow: NSWindow?
    private let screenManager = ScreenManager()
    private var controlsWindow: NSWindow!
    private let panelModel = DlockPanelModel()
    private var isPlacingDock = false
    private let accessGuide = AccessGuideController()

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
        HotkeyManager.shared.register()
        DockGuardian.shared.refresh()
        Task {
            _ = await restorePinnedDock()
            rebuildMenu()
        }
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

        let hostingController = NSHostingController(rootView: DlockPanelView(model: panelModel))
        hostingController.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dlock"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(NSSize(width: DlockPanelView.width, height: hostingController.view.fittingSize.height))
        window.center()
        controlsWindow = window
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
            controlsWindow.orderOut(nil)
        } else {
            showControlsWindow()
        }
    }

    private func showControlsWindow() {
        rebuildMenu()
        NSApp.activate(ignoringOtherApps: true)
        controlsWindow.makeKeyAndOrderFront(nil)
    }

    private func handle(_ action: DlockPanelModel.Action) {
        switch action {
        case .selectDisplay(let displayID): Task { await pinToDisplay(displayID) }
        case .setLocked(let locked): Task { await setLocked(locked) }
        case .setAutohide(let enabled): Task { await applyAutohide(enabled) }
        case .grantAccess: openAccessibilitySettings()
        case .showProfilesMenu: showProfilesMenu()
        case .showSettingsMenu: showSettingsMenu()
        case .quit: quitApp()
        }
    }

    // MARK: - Panel menus

    private func showProfilesMenu() {
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
        menu.addItem(ActionMenuItem("Launch at Login", isChecked: LaunchAtLoginManager.shared.isEnabled) { [weak self] in
            self?.toggleLaunchAtLogin()
        })
        menu.addItem(ActionMenuItem("Show Dlock in Dock", isChecked: showInDock) { [weak self] in
            self?.toggleShowInDock()
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
        menu.addItem(ActionMenuItem("Move Dock to Main Display", isEnabled: AccessibilityPermission.isGranted()) { [weak self] in
            Task { await self?.resetToMainDisplay() }
        })
        menu.addItem(ActionMenuItem("Live Diagnostics…") { [weak self] in self?.showDiagnostics() })
        menu.addItem(ActionMenuItem("Check for Updates…") { [weak self] in self?.checkForUpdates() })
        menu.addItem(ActionMenuItem("About Dlock") { [weak self] in self?.showAbout() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Hold ⌥ to let the Dock move · ⌃⌥D opens Dlock", isEnabled: false) {})
        popUpAtPointer(menu)
    }

    private func popUpAtPointer(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func setupScreenMonitoring() {
        screenManager.onScreenParametersChanged = { [weak self] in
            self?.rebuildMenu()
        }
        screenManager.onScreenDisconnected = { name in
            NotificationManager.shared.screenDisconnected(name: name)
        }
        screenManager.onScreenReconnected = { [weak self] screen in
            NotificationManager.shared.screenReconnected(name: screen.localizedName)
            Task {
                _ = await self?.restorePinnedDock()
                self?.rebuildMenu()
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

        let status: DlockPanelModel.LockStatus
        let title: String
        if !isGranted {
            status = .needsAccess
            title = "Accessibility access needed"
        } else if DockGuardian.shared.isGuardActive {
            status = .locked
            title = "Locked to \(pinnedScreen?.localizedName ?? "your display")"
        } else if pinnedID == nil {
            status = .unlocked
            title = "Dock not locked"
        } else if screens.count <= 1 {
            status = .singleDisplay
            title = "Single display"
        } else {
            status = .attention
            title = pinnedScreen == nil ? "Locked display disconnected" : "Lock needs attention"
        }
        let detail = isGranted
            ? DockGuardian.shared.statusSummary
            : "Dlock needs it to stop the Dock from following your pointer."

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

        panelModel.state = .init(
            displays: screens.enumerated().map { index, screen in
                .init(
                    id: screen.displayID,
                    name: screen.localizedName,
                    frame: screen.frame,
                    isMain: index == 0,
                    isBuiltIn: screen.directDisplayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
                )
            },
            pinnedDisplayID: pinnedScreen?.displayID ?? pinnedID,
            dockDisplayID: isGranted ? DockGuardian.shared.currentDockScreen()?.displayID : nil,
            orientation: orientation,
            autohideEnabled: autohide,
            status: status,
            statusTitle: title,
            statusDetail: detail,
            profiles: profiles
        )
    }

    // MARK: - Actions

    @objc private func showDiagnostics() {
        let window: NSWindow
        if let existing = diagnosticsWindow {
            window = existing
        } else {
            let text = NSTextField(wrappingLabelWithString: "")
            text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            text.maximumNumberOfLines = 0
            text.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                text.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                text.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                text.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
            ])
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Dlock Live Diagnostics"
            window.contentView = content
            window.center()
            diagnosticsWindow = window
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak text, weak window] _ in
                guard let text, window?.isVisible == true else { return }
                text.stringValue = DockGuardian.shared.diagnosticsText
            }
        }
        if let text = window.contentView?.subviews.first as? NSTextField {
            text.stringValue = DockGuardian.shared.diagnosticsText
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func setLocked(_ locked: Bool) async {
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
        guard !isPlacingDock else { return }
        guard let screen = NSScreen.screen(matching: displayID), await placeDock(on: screen) else {
            rebuildMenu()
            return
        }
        screenManager.pin(to: screen)
        panelModel.flash("Dock locked to \(screen.localizedName).")
        rebuildMenu()
    }

    private func applyAutohide(_ enabled: Bool) async {
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
        guard ProfileManager.shared.saveCurrentAsProfile(name: name) != nil else {
            panelModel.flash("Lock the Dock to a display before saving a profile.", isError: true)
            return
        }
        panelModel.flash("Saved profile \(name).")
        rebuildMenu()
    }

    private func deleteProfile(id: UUID) {
        guard let profile = ProfileManager.shared.profiles.first(where: { $0.id == id }) else { return }
        ProfileManager.shared.deleteProfile(id: id)
        panelModel.flash("Deleted \(profile.name).")
        rebuildMenu()
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

    @objc private func resetToMainDisplay() async {
        guard !isPlacingDock else { return }
        guard let primaryScreen = NSScreen.screens.first,
              await placeDock(on: primaryScreen) else { return }
        screenManager.resetPin()
        panelModel.flash("Dock unlocked and back on \(primaryScreen.localizedName).")
        rebuildMenu()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkAndNotify()
    }

    @objc private func openAccessibilitySettings() {
        guard !AccessibilityPermission.isGranted() else { return }
        showAccessibilityGuide()
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

    private func restorePinnedDock() async -> Bool {
        guard let screen = screenManager.pinnedScreen else { return true }
        return await placeDock(on: screen)
    }

    private func placeDock(on screen: NSScreen) async -> Bool {
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
