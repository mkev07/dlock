import AppKit

@MainActor
final class AboutFlagTooltip: NSView {
    private let popover = NSPopover()
    private let label = NSTextField(labelWithString: "")
    private var hoverArea: NSTrackingArea?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    static func text(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Indian/Mauritius")
        formatter.dateFormat = "h:mm a"
        return "🇲🇺 Mauritius GMT+4 • \(formatter.string(from: date))"
    }

    static func install(in textView: NSTextView) {
        for previous in textView.subviews.compactMap({ $0 as? AboutFlagTooltip }) {
            previous.dismiss()
            previous.removeFromSuperview()
        }
        let range = (textView.string as NSString).range(of: "🇲🇺")
        guard range.location != NSNotFound,
              let layout = textView.layoutManager,
              let container = textView.textContainer else { return }
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        guard !bounds.isEmpty else { return }
        let hover = AboutFlagTooltip(frame: bounds.insetBy(dx: -2, dy: -2))
        textView.addSubview(hover)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let content = NSViewController()
        content.view = NSView()
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        content.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.view.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.view.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.view.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: content.view.bottomAnchor, constant: -8)
        ])
        popover.contentViewController = content
        popover.behavior = .applicationDefined
        popover.animates = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Mauritius, GMT+4")
        updateText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        dismiss()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let window else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.dismiss() }
                })
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard window?.isKeyWindow == true else { return }
        updateText()
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateText() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    override func mouseExited(with event: NSEvent) {
        dismiss()
    }

    private func updateText() {
        label.stringValue = Self.text()
        setAccessibilityHelp(label.stringValue)
        popover.contentSize = NSSize(width: ceil(label.intrinsicContentSize.width) + 24,
                                     height: ceil(label.intrinsicContentSize.height) + 16)
    }

    private func dismiss() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        popover.close()
    }

    deinit {
        refreshTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
