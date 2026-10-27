import AppKit
import SwiftUI

/// A small window that stands beside System Settings while the user grants
/// Accessibility access. System Settings takes the front when it opens, so the
/// steps live in a floating panel the user can still see, together with a
/// card that drags Dlock.app straight into the permission list.
@MainActor
final class AccessGuideController {

    private final class Model: ObservableObject {
        @Published var isGranted = false
    }

    private let model = Model()
    private var panel: NSPanel?
    private var closeAfterGrant: DispatchWorkItem?

    func show() {
        closeAfterGrant?.cancel()
        model.isGranted = AccessibilityPermission.isGranted()
        AccessibilityPermission.openSettings()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
    }

    /// Shows the success state briefly, then gets out of the way.
    func markGranted() {
        guard let panel, panel.isVisible else { return }
        model.isGranted = true
        let close = DispatchWorkItem { [weak self] in self?.close() }
        closeAfterGrant = close
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: close)
    }

    func close() {
        closeAfterGrant?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Turn on Accessibility"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        // Panels hide when their app deactivates by default, and opening
        // System Settings deactivates Dlock.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.standardWindowButton(.closeButton)?.isHidden = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let hosting = NSHostingView(rootView: AccessGuideView(model: model) { [weak self] in
            self?.close()
        })
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []
        }
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// Top-right of the main screen, clear of a centered System Settings window.
    private func position(_ panel: NSPanel) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 32, y: visible.maxY - size.height - 32))
    }

    // MARK: - View

    private struct AccessGuideView: View {
        @ObservedObject var model: Model
        let onDone: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !model.isGranted {
                    DragCard()
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        step(1, "Drag Dlock.app into the list.")
                        step(2, "Turn the switch on.")
                        step(3, "Already listed but not working? Select it, click −, then drag it in again.")
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    if !model.isGranted {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    }
                    if model.isGranted {
                        Button("Done", action: onDone)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Done", action: onDone)
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 22)
            .padding(.top, 34)
            .padding(.bottom, 20)
            .frame(width: 360)
            .animation(.easeInOut(duration: 0.25), value: model.isGranted)
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 12) {
                // Matches the Accessibility icon in System Settings.
                Image(systemName: model.isGranted ? "checkmark" : "accessibility")
                    .font(.system(size: model.isGranted ? 17 : 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(model.isGranted ? Color.green.gradient : Color.blue.gradient)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isGranted ? "Accessibility is on" : "Turn on Accessibility")
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.isGranted
                         ? "Dlock can keep the Dock in place now."
                         : "System Settings is open at Accessibility.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func step(_ number: Int, _ text: String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
        }
    }

    private struct DragCard: View {
        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 52, height: 52)
                Text("Dlock.app")
                    .font(.system(size: 13, weight: .semibold))
                Text("Drag to add")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.22 : 0.12), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(90))
                    .padding(10)
            }
            .overlay(BundleDragSource())
            .onHover { isHovering = $0 }
            .help("Drag Dlock into System Settings, or click to show it in Finder")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dlock.app. Drag into System Settings, or press to show it in Finder.")
            .accessibilityAddTraits(.isButton)
        }
    }
}

/// Starts a real file drag of the app bundle, which is what the System
/// Settings privacy list accepts. A plain click reveals the bundle in Finder.
private struct BundleDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> BundleDragView { BundleDragView() }
    func updateNSView(_ nsView: BundleDragView, context: Context) {}
}

private final class BundleDragView: NSView, NSDraggingSource {
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        mouseDownEvent = nil

        let bundleURL = Bundle.main.bundleURL
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        icon.size = NSSize(width: 52, height: 52)
        let point = convert(down.locationInWindow, from: nil)
        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        item.setDraggingFrame(NSRect(x: point.x - 26, y: point.y - 26, width: 52, height: 52), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
