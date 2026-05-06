import AppKit
import CoreGraphics

class DockController {

    static let shared = DockController()

    private init() {}

    // MARK: - Screen Pin

    func moveDockToScreen(_ screen: NSScreen) {
        let frame = screen.frame
        let targetPoint = CGPoint(x: frame.midX, y: frame.midY)
        warpCursor(to: targetPoint)
        restartDock()
    }

    private func warpCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("DLock: failed to restart Dock: \(error)")
        }
    }

    // MARK: - Orientation

    func setOrientation(_ orientation: DockOrientation) {
        runDefaults("write", "com.apple.dock", "orientation", "-string", orientation.rawValue)
    }

    func getOrientation() -> DockOrientation {
        let output = runDefaultsRead("com.apple.dock", "orientation")
        return DockOrientation(rawValue: output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .bottom
    }

    // MARK: - Auto-hide

    func setAutohide(_ enabled: Bool) {
        runDefaults("write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false")
    }

    func getAutohide() -> Bool {
        let output = runDefaultsRead("com.apple.dock", "autohide")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: - Apply Profile

    func apply(profile: DLockProfile) {
        setOrientation(profile.orientation)
        setAutohide(profile.autohide)
        if let screen = NSScreen.screens.first(where: { $0.displayID == profile.displayID }) {
            moveDockToScreen(screen)
        } else {
            restartDock()
        }
    }

    func applySettings(profile: DLockProfile) {
        setOrientation(profile.orientation)
        setAutohide(profile.autohide)
        restartDock()
    }

    // MARK: - Helpers

    private func runDefaults(_ args: String...) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("DLock: defaults error: \(error)")
        }
    }

    private func runDefaultsRead(_ args: String...) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
