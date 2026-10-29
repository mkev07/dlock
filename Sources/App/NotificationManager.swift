import Foundation
import UserNotifications

class NotificationManager {

    static let shared = NotificationManager()

    private var isAuthorized = false

    private init() {
        requestAuthorization()
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("DLock: notification authorization error: \(error)")
            }
            self.isAuthorized = granted
        }
    }

    func screenDisconnected(name: String) {
        send(title: "Pinned Screen Disconnected", body: "\"\(name)\" is no longer connected. Dlock kept the preference for when it returns.")
    }

    func screenReconnected(name: String, restored: Bool) {
        send(title: "Pinned Screen Reconnected", body: Self.reconnectionMessage(name: name, restored: restored))
    }

    static func reconnectionMessage(name: String, restored: Bool) -> String {
        if restored {
            return "The Dock is back on \"\(name)\"."
        }
        return "\"\(name)\" is connected, but Dlock could not confirm the Dock returned. Open Dlock and select this display to retry."
    }

    func profileActivated(name: String) {
        send(title: "Profile Activated", body: "\"\(name)\" is now active.")
    }

    private func send(title: String, body: String) {
        guard isAuthorized else {
            requestAuthorization()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("DLock: failed to send notification: \(error)")
            }
        }
    }
}
