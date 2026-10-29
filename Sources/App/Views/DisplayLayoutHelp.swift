import SwiftUI

struct DisplayLayoutHelp: View {
    @ObservedObject var model: DlockPanelModel
    let onSelect: (String) -> Void
    @State private var isPresented = false
    private var state: DlockPanelModel.State { model.state }

    private var blockedDisplay: DlockPanelModel.Display? {
        guard state.orientation == .bottom else { return nil }
        let frames = state.displays.map { DockLayoutGeometry.quartzFrame(fromAppKit: $0.frame) }
        let blocked = state.displays.filter {
            DockLayoutGeometry.placementPoint(in: DockLayoutGeometry.quartzFrame(fromAppKit: $0.frame),
                orientation: .bottom, displays: frames) == nil
        }
        return blocked.first { $0.id == model.layoutHelpDisplayID }
            ?? blocked.first { $0.id == state.pinnedDisplayID } ?? blocked.first
    }

    var body: some View {
        VStack(spacing: 0) {
        if !state.displaysHaveSeparateSpaces && state.displays.count > 1 {
            Button {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return }
                NSWorkspace.shared.open(url)
            } label: {
                Label("Check Separate Spaces…", systemImage: "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .help("Displays have separate Spaces is off. Per-display Dock placement may not work. Check Desktop & Dock settings; macOS may require signing out for a change to take effect.")
        }
        if let target = blockedDisplay {
            Button {
                isPresented.toggle()
            } label: {
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: "rectangle.2.swap")
                    Text("Layout tip for \(target.name)")
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Explains why the bottom Dock edge is blocked and shows a suggested display arrangement")
            .background(alignment: .trailing) {
                // Keep the anchor outside the button label so the popover's
                // controls do not inherit the button's styling or action.
                Color.clear
                    .frame(width: 8, height: 12)
                    .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                        DisplayLayoutExplanation(state: state, targetID: target.id) {
                            isPresented = false
                            onSelect(target.id)
                        }
                    }
                    .padding(.trailing, 9)
            }
            .padding(.bottom, 8)
            .onChange(of: model.layoutHelpDisplayID) { displayID in
                if displayID != nil { isPresented = true }
            }
            .onChange(of: isPresented) { visible in
                if !visible { model.layoutHelpDisplayID = nil }
            }
        }
        }
    }
}

private struct DisplayLayoutExplanation: View {
    let state: DlockPanelModel.State
    let targetID: String
    let onRetry: () -> Void
    @State private var showSuggestion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: DlockPanelModel.Display? {
        state.displays.first { $0.id == targetID }
    }

    private var suggestion: DockLayoutGeometry.Suggestion? {
        guard let target else { return nil }
        return DockLayoutGeometry.bottomEdgeSuggestion(
            for: DockLayoutGeometry.quartzFrame(fromAppKit: target.frame),
            displays: state.displays.map { DockLayoutGeometry.quartzFrame(fromAppKit: $0.frame) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Give the Dock an exposed edge")
                .font(.system(size: 14, weight: .semibold))
            if let target {
                Text("Another display covers the bottom edge of \(target.name). Dlock cannot summon the bottom Dock there in this arrangement.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if suggestion != nil {
                LayoutArrangementTabs(showSuggestion: $showSuggestion)
            }
            diagram
            if let suggestion {
                Text("In System Settings → Displays → Arrange, move this screen to the \(suggestion.direction), until part of its bottom edge is exposed.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Try placing this screen beside the others, or choose a display with an exposed bottom edge.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Illustration only. Your display arrangement stays unchanged. After arranging, retry your screen in Dlock.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Displays…") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
                    NSWorkspace.shared.open(url)
                }
                Spacer()
                Button("Retry display", action: onRetry)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
        .modifier(LayoutPopoverSurface())
        .onChange(of: state.displays) { _ in showSuggestion = false }
        .onChange(of: targetID) { _ in showSuggestion = false }
    }

    private var diagram: some View {
        let frames = state.displays.map { $0.frame }
        let suggestedFrame = suggestion.map { DockLayoutGeometry.quartzFrame(fromAppKit: $0.frame) }
        let bounds = (frames + [suggestedFrame].compactMap { $0 }).reduce(CGRect.null) { $0.union($1) }
        let scale = min(250 / max(1, bounds.width), 125 / max(1, bounds.height))
        return VStack(spacing: 10) {
            GeometryReader { _ in
                ForEach(Array(state.displays.enumerated()), id: \.element.id) { index, display in
                    let frame = showSuggestion && display.id == targetID ? (suggestedFrame ?? display.frame) : display.frame
                    let width = max(8, frame.width * scale - 3)
                    let height = max(8, frame.height * scale - 3)
                    let exposedWidth = min(14, max(5, abs(frame.minX - display.frame.minX) * scale - 5))
                    LayoutDiagramTile(number: index + 1, isTarget: display.id == targetID,
                                      showsSuggestion: showSuggestion, direction: suggestion?.direction,
                                      exposedWidth: exposedWidth)
                        .frame(width: width, height: height)
                        .position(x: (frame.minX - bounds.minX) * scale + width / 2,
                                  y: (bounds.maxY - frame.maxY) * scale + height / 2)
                }
            }
            .frame(width: bounds.width * scale, height: bounds.height * scale)
            .animation(reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.25), value: showSuggestion)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(showSuggestion ? "Suggested layout: move the selected screen \(suggestion?.direction ?? "sideways") to expose its bottom edge." : "Current layout: the selected screen has a covered bottom edge.")
            diagramLegend
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var diagramLegend: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(showSuggestion ? Color.accentColor : .orange)
                .frame(width: 14, height: 3)
                .accessibilityHidden(true)
            Text(showSuggestion ? "Exposed bottom edge" : "Covered bottom edge")
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
    }
}


private struct LayoutDiagramTile: View {
    let number: Int
    let isTarget: Bool
    let showsSuggestion: Bool
    let direction: String?
    let exposedWidth: CGFloat

    private var edgeAlignment: Alignment {
        guard showsSuggestion else { return .bottom }
        return direction == "left" ? .bottomLeading : .bottomTrailing
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isTarget ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isTarget ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1))
            .overlay(Text("\(number)").font(.system(size: 10, weight: .semibold)))
            .overlay(alignment: edgeAlignment) {
                if isTarget {
                    Capsule()
                        .fill(showsSuggestion ? Color.accentColor : .orange)
                        .frame(width: showsSuggestion ? exposedWidth : 22, height: 3)
                        .padding(3)
                }
            }
    }
}


private struct LayoutPopoverSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            content.presentationBackground(Color(nsColor: .controlBackgroundColor))
        } else {
            content
        }
    }
}

private struct LayoutArrangementTabs: View {
    @Binding var showSuggestion: Bool
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 2) {
            tab("Current arrangement", suggested: false)
            tab("Suggested layout", suggested: true)
        }
        .padding(3)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showSuggestion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display layout")
    }

    private func tab(_ title: String, suggested: Bool) -> some View {
        let selected = showSuggestion == suggested
        return Button {
            showSuggestion = suggested
        } label: {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity, minHeight: 27)
                .background {
                    if selected {
                        selectionSurface
                            .matchedGeometryEffect(id: "selected-layout", in: selection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onMoveCommand { direction in
            if direction == .left { showSuggestion = false }
            if direction == .right { showSuggestion = true }
        }
    }

    @ViewBuilder
    private var selectionSurface: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            Capsule().fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
        }
    }
}
