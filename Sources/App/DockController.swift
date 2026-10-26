import AppKit

final class DockController {

    static let shared = DockController()

    private init() {}

    func restartDock() {
        let previousPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                print("Dlock: Dock restart exited with status \(task.terminationStatus)")
                return
            }
        } catch {
            print("Dlock: failed to restart Dock: \(error)")
            return
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let currentPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .first?.processIdentifier
            if let currentPID, currentPID != previousPID { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    func setOrientation(_ orientation: DockOrientation) {
        runDefaults("write", "com.apple.dock", "orientation", "-string", orientation.rawValue)
    }

    func getOrientation() -> DockOrientation {
        let output = runDefaultsRead("com.apple.dock", "orientation")
        return DockOrientation(rawValue: output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .bottom
    }

    func setAutohide(_ enabled: Bool) {
        runDefaults("write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false")
    }

    func getAutohide() -> Bool {
        let output = runDefaultsRead("com.apple.dock", "autohide")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    func applySettings(profile: DLockProfile) {
        setOrientation(profile.orientation)
        setAutohide(profile.autohide)
        restartDock()
    }

    @discardableResult
    private func runDefaults(_ args: String...) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                print("Dlock: defaults exited with status \(task.terminationStatus)")
                return false
            }
            return true
        } catch {
            print("Dlock: defaults error: \(error)")
            return false
        }
    }

    private func runDefaultsRead(_ args: String...) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
