import AppKit
import ApplicationServices

/// Central handling for Accessibility (TCC) permission, which Dlock requires
/// for the global hotkey, Dock-edge event filtering, and Dock position checks.
///
/// Lifecycle:
///  * `isGranted()` reflects the current trust state.
///  * `prompt()` shows the system-managed permission prompt once.
///  * `openSettings()` deep-links into System Settings → Privacy → Accessibility.
///  * `waitForGrant(onGranted:)` polls every second until trust flips on, then
///    runs the callback exactly once. Multiple callers queue up.
enum AccessibilityPermission {

    static func isGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system prompt asking the user to enable Accessibility for
    /// this app. Safe to call when already granted (just returns true).
    @discardableResult
    static func prompt() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: NSDictionary = [key: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Opens System Settings directly on the Accessibility privacy pane so
    /// the user only needs to flip the toggle.
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Grant polling

    private static var pollTimer: DispatchSourceTimer?
    private static var pendingCallbacks: [() -> Void] = []

    /// Runs `onGranted` immediately if Accessibility is already granted,
    /// otherwise on the first poll tick after the user grants it.
    static func waitForGrant(_ onGranted: @escaping () -> Void) {
        if isGranted() {
            onGranted()
            return
        }
        pendingCallbacks.append(onGranted)
        startPolling()
    }

    private static func startPolling() {
        guard pollTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        t.setEventHandler {
            guard isGranted() else { return }
            t.cancel()
            pollTimer = nil
            let callbacks = pendingCallbacks
            pendingCallbacks.removeAll()
            callbacks.forEach { $0() }
        }
        t.resume()
        pollTimer = t
    }
}
