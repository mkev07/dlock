import Foundation

@main struct ReconnectMessageChecks {
    static func main() {
        let restored = NotificationManager.reconnectionMessage(name: "Test Display", restored: true)
        let unconfirmed = NotificationManager.reconnectionMessage(name: "Test Display", restored: false)
        precondition(restored.contains("Test Display") && restored.contains("back on"))
        precondition(unconfirmed.contains("could not confirm") && unconfirmed.contains("select this display to retry"))
        precondition(!unconfirmed.contains("is back on"))
        precondition(!restored.contains("Move the Dock") && !unconfirmed.contains("Move the Dock"))
        print("PASS: confirmed restoration names the display")
        print("PASS: unconfirmed restoration offers retry without claiming success")
        print("PASS: no manual Dock movement instructions")
    }
}
