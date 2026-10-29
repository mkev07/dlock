import AppKit
import Combine

/// State and intents for the menu bar panel. AppDelegate owns the Dock logic
/// and pushes a fresh `State` whenever something changes; the SwiftUI panel
/// only renders it and sends `Action`s back.
@MainActor
final class DlockPanelModel: ObservableObject {

    struct Display: Identifiable, Equatable {
        let id: String
        let name: String
        /// Global frame in AppKit coordinates (origin bottom-left).
        let frame: CGRect
        let isMain: Bool
        let isBuiltIn: Bool
    }

    struct Profile: Identifiable, Equatable {
        let id: UUID
        let name: String
        let detail: String
        let isActive: Bool
    }

    enum LockStatus: Equatable {
        case needsAccess
        case locked
        case unlocked
        case singleDisplay
        case attention
    }

    /// A configured pin alone does not prove that the Dock is locked there.
    static func resolveLockStatus(hasAccess: Bool, pinnedDisplayID: String?,
                                  dockDisplayID: String?, connectedDisplayIDs: [String],
                                  guardActive: Bool) -> LockStatus {
        guard hasAccess else { return .needsAccess }
        guard let pinnedDisplayID else { return .unlocked }
        guard connectedDisplayIDs.contains(pinnedDisplayID) else { return .attention }
        guard connectedDisplayIDs.count > 1 else { return .singleDisplay }
        guard guardActive, dockDisplayID == pinnedDisplayID else { return .attention }
        return .locked
    }

    struct State: Equatable {
        var isLicensed = false
        var displays: [Display] = []
        var pinnedDisplayID: String?
        /// The display the Dock is currently on, when Dlock can read it.
        var dockDisplayID: String?
        var orientation: DockOrientation = .bottom
        /// nil when the current value could not be read.
        var autohideEnabled: Bool?
        var sizeLockEnabled: Bool?
        var displaysHaveSeparateSpaces = true
        var status: LockStatus = .unlocked
        var statusTitle = ""
        var statusDetail = ""
        var profiles: [Profile] = []

        var isAccessibilityGranted: Bool { status != .needsAccess }
        var pinnedDisplayName: String? {
            displays.first { $0.id == pinnedDisplayID }?.name
        }
        var canUseDockFeatures: Bool { isLicensed && isAccessibilityGranted }
        var isLocked: Bool { isLicensed && pinnedDisplayName != nil }
    }

    struct Feedback: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    enum Action {
        case selectDisplay(String)
        case setLocked(Bool)
        case setAutohide(Bool)
        case setSizeLock(Bool)
        case setOrientation(DockOrientation)
        case grantAccess
        case showLicense
        case showProfilesMenu
        case showSettingsMenu
        case quit
    }

    @Published var state = State()
    @Published var layoutHelpDisplayID: String?
    @Published private(set) var feedback: Feedback?

    var onAction: ((Action) -> Void)?

    private var feedbackDismissal: DispatchWorkItem?

    /// Actions run on the next turn of the run loop so modal alerts never start
    /// inside a SwiftUI gesture or menu-tracking callback.
    func send(_ action: Action) {
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }

    func flash(_ message: String, isError: Bool = false) {
        let feedback = Feedback(message: message, isError: isError)
        self.feedback = feedback

        feedbackDismissal?.cancel()
        let dismissal = DispatchWorkItem { [weak self] in
            guard self?.feedback?.id == feedback.id else { return }
            self?.feedback = nil
        }
        feedbackDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6 : 3), execute: dismissal)
    }

    func dismissFeedback() {
        feedbackDismissal?.cancel()
        feedback = nil
    }
}
