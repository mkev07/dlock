import SwiftUI

struct LicenseView: View {
    @ObservedObject var manager: LicenseManager
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("License — Testing").font(.headline)
            Text("Local testing only. Activate a valid test license to enable Dock features. No trial or live purchase is enabled.")
                .font(.callout).foregroundStyle(.secondary)
            Text("One active Mac • Lifetime • All future updates")
                .font(.callout)
            Text("Checks daily • Up to 30 days offline after verification")
                .font(.caption).foregroundStyle(.secondary)
            if !manager.hasActivation {
                HStack {
                    SecureField("Test license key", text: $manager.enteredKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFocused)
                    Button("Paste") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            manager.enteredKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            keyFocused = true
                        }
                    }
                    .help("Paste a license key from the clipboard")
                }
                .disabled(manager.isBusy || !manager.isConfigured)
                if manager.hasSavedKey {
                    Text("A test key is saved. Activate again or paste a replacement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(manager.message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("License status: \(manager.message)")
            if manager.isBusy { ProgressView("Contacting test licensing service…").controlSize(.small) }
            HStack {
                if manager.hasActivation {
                    Button("Check Validity") { Task { await manager.perform("validate") } }
                    Button("Deactivate This Mac") { Task { await manager.perform("deactivate") } }
                } else {
                    Button("Activate Test License") { Task { await manager.perform("activate") } }
                        .disabled(!manager.hasSavedKey && manager.enteredKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if manager.hasSavedKey {
                        Button("Clear Unactivated Key") { manager.clearUnactivatedKey() }
                    }
                }
            }
            .disabled(manager.isBusy || !manager.isConfigured)
            Text("Start the local test service before activating. License keys and the random installation ID are stored in this Mac’s Keychain, not synced through iCloud. No usage analytics are sent.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 430)
        .onAppear { keyFocused = true }
    }
}
