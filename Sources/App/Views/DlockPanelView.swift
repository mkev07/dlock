import AppKit
import SwiftUI

/// The menu bar panel, modeled on the system Wi‑Fi and Bluetooth menus: a
/// master switch, a picture of the display arrangement, a list of displays,
/// and compact rows for the rest.
struct DlockPanelView: View {
    @ObservedObject var model: DlockPanelModel
    @ObservedObject private var updater = UpdateChecker.shared

    static let width: CGFloat = 300

    private var state: DlockPanelModel.State { model.state }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !state.isLicensed {
                MenuRow(title: "Activate License…", showsChevron: true) { model.send(.showLicense) }
                    .padding(.bottom, 4)
            } else if !state.isAccessibilityGranted {
                AccessRow { model.send(.grantAccess) }
                    .padding(.bottom, 4)
            }

            Group {
                if !state.displays.isEmpty {
                    DisplayMap(state: state) { model.send(.selectDisplay($0)) }
                        .animation(.easeInOut(duration: 0.2), value: state)
                        .padding(.top, 4)
                        .padding(.bottom, 10)
                }

                PanelDivider()
                SectionHeader(title: "Displays")
                ForEach(state.displays) { display in
                    DisplayRow(
                        display: display,
                        isPinned: display.id == state.pinnedDisplayID,
                        isVerified: state.status == .locked,
                        hasDock: display.id == state.dockDisplayID
                    ) {
                        model.send(.selectDisplay(display.id))
                    }
                    .animation(.easeInOut(duration: 0.2), value: state)
                }
            }
            .disabled(!state.canUseDockFeatures)
            .opacity(state.canUseDockFeatures ? 1 : 0.45)

            PanelDivider()
            PositionRow(orientation: state.orientation) {
                model.send(.setOrientation($0))
            }
            .disabled(!state.canUseDockFeatures)
            AutohideRow(isOn: state.autohideEnabled) { model.send(.setAutohide($0)) }
                .disabled(!state.canUseDockFeatures)

            PanelDivider()
            MenuRow(title: "Profiles", value: state.profiles.first(where: \.isActive)?.name, showsChevron: true) {
                model.send(.showProfilesMenu)
            }
            .disabled(!state.canUseDockFeatures)
            MenuRow(title: "Settings", showsChevron: true) {
                model.send(.showSettingsMenu)
            }
            PanelDivider()
            UpdateStatusRow(updater: updater)
            PanelDivider()
            MenuRow(title: "Quit Dlock", shortcut: "⌘Q") {
                model.send(.quit)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if let feedback = model.feedback {
                    FeedbackToast(feedback: feedback) { model.dismissFeedback() }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.feedback)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image("menubar_logo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text("Dlock")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(state.status == .attention ? Color.orange : Color.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Toggle("Dock Lock", isOn: Binding(
                get: { state.isLocked },
                set: { model.send(.setLocked($0)) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!state.canUseDockFeatures || state.displays.isEmpty)
        }
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        if !state.isLicensed { return "Activate your license to enable Dlock" }
        switch state.status {
        case .needsAccess: return "Waiting for Accessibility access"
        case .locked: return "The Dock stays on\n\(state.pinnedDisplayName ?? "your display")"
        case .unlocked: return "The Dock follows the pointer"
        case .singleDisplay: return "Only one display is connected"
        case .attention: return state.statusDetail
        }
    }
}

// MARK: - Rows

private struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.top, 2)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A round icon like the ones in the system Wi‑Fi and Bluetooth menus.
private struct CircleGlyph: View {
    let symbol: String
    let isSelected: Bool
    var tint: Color = .accentColor
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(isSelected ? tint : Color.primary.opacity(0.1)))
    }
}

/// Hover highlight shared by every clickable row.
private struct RowHighlight: ViewModifier {
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isHovering && isEnabled ? 0.09 : 0))
            )
            .onHover { isHovering = $0 }
    }
}

private struct AccessRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                CircleGlyph(symbol: "hand.raised.fill", isSelected: true, tint: .orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Grant Accessibility Access…")
                        .font(.system(size: 13))
                    Text("Dlock needs it to keep the Dock in place")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .modifier(RowHighlight())
        }
        .buttonStyle(.plain)
    }
}

private struct DisplayRow: View {
    let display: DlockPanelModel.Display
    let isPinned: Bool
    let isVerified: Bool
    let hasDock: Bool
    let action: () -> Void

    private var detail: String? {
        if isPinned { return isVerified ? "Dock locked here" : "Selected display" }
        if hasDock { return "Dock is here" }
        return nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                CircleGlyph(symbol: display.isBuiltIn ? "laptopcomputer" : "display", isSelected: isPinned)
                VStack(alignment: .leading, spacing: 0) {
                    Text(display.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if isPinned {
                    Image(systemName: isVerified ? "lock.fill" : "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .frame(minHeight: 34)
            .modifier(RowHighlight())
        }
        .buttonStyle(.plain)
        .help(isPinned ? (isVerified ? "The Dock is locked to \(display.name)" : "Selected for Dock Lock: \(display.name)") : "Lock the Dock to \(display.name)")
        .accessibilityLabel(display.name + (detail.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }
}

private struct UpdateStatusRow: View {
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if updater.state == .checking {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Checking for updates")
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(updater.state.title).font(.system(size: 11, weight: .medium))
                Text(updater.state.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(updater.state.actionTitle) { updater.performAction() }
                .controlSize(.small)
                .disabled(updater.state == .checking)
                .accessibilityLabel("\(updater.state.actionTitle): \(updater.state.title)")
        }
        .padding(9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 4)
    }
}

private struct PositionRow: View {
    let orientation: DockOrientation
    let onChange: (DockOrientation) -> Void

    var body: some View {
        HStack {
            Text("Position")
                .font(.system(size: 13))
            Spacer()
            HStack(spacing: 6) {
                ForEach([DockOrientation.left, .bottom, .right], id: \.self) { position in
                    Button { onChange(position) } label: {
                        CircleGlyph(symbol: symbol(for: position), isSelected: orientation == position, size: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dock position \(position.displayName)")
                    .accessibilityValue(orientation == position ? "Selected" : "Not selected")
                    .accessibilityAddTraits(orientation == position ? [.isSelected] : [])
                    .help("Move Dock to \(position.displayName)")
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
    }

    private func symbol(for position: DockOrientation) -> String {
        switch position {
        case .left: return "rectangle.leftthird.inset.filled"
        case .bottom: return "rectangle.bottomthird.inset.filled"
        case .right: return "rectangle.rightthird.inset.filled"
        }
    }
}

private struct AutohideRow: View {
    let isOn: Bool?
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text("Auto-hide")
                .font(.system(size: 13))
            Spacer()
            Toggle("Auto-hide", isOn: Binding(
                get: { isOn ?? false },
                set: { onChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(isOn == nil)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .help(isOn == nil ? "Dlock couldn’t read the current auto-hide setting" : "Hide the Dock until the pointer reaches it")
    }
}

private struct MenuRow: View {
    let title: String
    var value: String?
    var shortcut: String?
    var showsChevron = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .modifier(RowHighlight())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Display map

/// A scaled-down copy of the real display arrangement from System Settings.
private struct DisplayMap: View {
    let state: DlockPanelModel.State
    let onSelect: (String) -> Void

    private let maxSize = CGSize(width: 230, height: 72)
    private let gap: CGFloat = 4

    var body: some View {
        let bounds = state.displays.reduce(CGRect.null) { $0.union($1.frame) }
        let scale = min(maxSize.width / bounds.width, maxSize.height / bounds.height)
        let dockID = state.dockDisplayID

        ZStack(alignment: .topLeading) {
            ForEach(state.displays) { display in
                let rect = CGRect(
                    x: (display.frame.minX - bounds.minX) * scale,
                    y: (bounds.maxY - display.frame.maxY) * scale,
                    width: display.frame.width * scale,
                    height: display.frame.height * scale
                ).insetBy(dx: gap / 2, dy: gap / 2)

                VStack(spacing: 4) {
                    DisplayTile(
                        display: display,
                        isPinned: display.id == state.pinnedDisplayID,
                        showsDock: display.id == dockID,
                        orientation: state.orientation
                    ) {
                        onSelect(display.id)
                    }
                    .frame(width: rect.width, height: rect.height)
                    Text(display.isBuiltIn ? "Built-in" : display.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(display.name)
                }
                .frame(width: rect.width)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: bounds.width * scale, height: bounds.height * scale + 18, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }
}

private struct DisplayTile: View {
    let display: DlockPanelModel.Display
    let isPinned: Bool
    let showsDock: Bool
    let orientation: DockOrientation
    let action: () -> Void

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                shape.fill(isPinned ? Color.accentColor.opacity(0.18) : Color.primary.opacity(isHovering ? 0.11 : 0.06))
                if showsDock {
                    DockBar(orientation: orientation, color: isPinned ? .accentColor : Color.secondary)
                }
                shape.strokeBorder(
                    isPinned ? Color.accentColor : Color.primary.opacity(isHovering ? 0.32 : 0.18),
                    lineWidth: isPinned ? 1.5 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(display.name)
        .accessibilityLabel(display.name)
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }
}

/// A capsule drawn along the edge of a screen thumbnail to represent the Dock.
private struct DockBar: View {
    let orientation: DockOrientation
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let thickness = max(3, min(size.width, size.height) * 0.08)
            let inset: CGFloat = 3
            switch orientation {
            case .bottom:
                Capsule()
                    .fill(color)
                    .frame(width: size.width * 0.5, height: thickness)
                    .position(x: size.width / 2, y: size.height - thickness / 2 - inset)
            case .left:
                Capsule()
                    .fill(color)
                    .frame(width: thickness, height: size.height * 0.55)
                    .position(x: thickness / 2 + inset, y: size.height / 2)
            case .right:
                Capsule()
                    .fill(color)
                    .frame(width: thickness, height: size.height * 0.55)
                    .position(x: size.width - thickness / 2 - inset, y: size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Feedback

private struct FeedbackToast: View {
    let feedback: DlockPanelModel.Feedback
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(feedback.isError ? Color.red : Color.green)
            Text(feedback.message)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
    }
}
