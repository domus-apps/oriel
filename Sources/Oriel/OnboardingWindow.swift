import AppKit
import Carbon.HIToolbox

/* First-run onboarding: what Oriel is, what snapping looks like, the
   default shortcuts, and the Accessibility permission gate (it's how
   windows are read and moved). The window has no close button and refuses
   every close attempt — the only way out is granting access and clicking
   Start, and completion is persisted only at that click, so quitting (or
   force-quitting) mid-onboarding brings the onboarding back on the next
   launch. */
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onComplete: () -> Void
    private var pollTimer: Timer?

    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var requestButton = NSButton(
        title: "Request Accessibility Access", target: self,
        action: #selector(requestAccess))
    private lazy var settingsLink = NSButton(
        title: "Open Privacy & Security Settings…", target: self,
        action: #selector(openSystemSettings))
    private lazy var startButton = NSButton(
        title: "Start Using Oriel", target: self, action: #selector(start))

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        /* No .closable: the traffic-light close button never appears. */
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 596),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()

        refreshPermissionState()
        /* Permission grants don't notify; polling once a second is the
           standard idiom (the System Settings toggle takes effect live). */
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            self?.refreshPermissionState()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /* The gate: no closing until onboarding is completed via start(). */
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    // MARK: - Content

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Welcome to Oriel")
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let intro = NSTextField(
            wrappingLabelWithString:
                "Oriel arranges your windows from the keyboard: snap to halves, "
                + "maximize, center, and move across displays — keeping each "
                + "window's size and relative position intact.")
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = .secondaryLabelColor
        intro.alignment = .center
        intro.preferredMaxLayoutWidth = 470

        let illustration = OnboardingIllustrationView()
        illustration.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            illustration.widthAnchor.constraint(equalToConstant: 480),
            illustration.heightAnchor.constraint(equalToConstant: 200),
        ])

        let shortcutRow = NSStackView(
            views: [
                labelView("Press"),
                keycap("⌃"), keycap("⌥"), keycap("→"),
                labelView("to snap right — customize in Settings"),
            ])
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 6

        statusLabel.font = .systemFont(ofSize: 13)
        requestButton.bezelStyle = .rounded
        requestButton.keyEquivalent = "\r"
        settingsLink.isBordered = false
        settingsLink.contentTintColor = .linkColor
        settingsLink.font = .systemFont(ofSize: 12)

        let permissionBox = NSStackView(
            views: [statusLabel, requestButton, settingsLink])
        permissionBox.orientation = .vertical
        permissionBox.alignment = .centerX
        permissionBox.spacing = 8

        startButton.bezelStyle = .rounded
        startButton.controlSize = .large

        let stack = NSStackView(
            views: [title, intro, illustration, shortcutRow, permissionBox, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(22, after: intro)
        stack.setCustomSpacing(24, after: shortcutRow)
        stack.setCustomSpacing(20, after: permissionBox)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])
        return container
    }

    private func labelView(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func keycap(_ symbol: String) -> NSView {
        KeycapView(symbol: symbol)
    }

    // MARK: - Permission gate

    private func refreshPermissionState() {
        let trusted = AXIsProcessTrusted()
        statusLabel.stringValue =
            trusted
            ? "✓ Accessibility access granted"
            : "Oriel needs Accessibility access to read and move windows."
        statusLabel.textColor = trusted ? .systemGreen : .labelColor
        requestButton.isHidden = trusted
        settingsLink.isHidden = trusted
        startButton.isEnabled = trusted
        startButton.keyEquivalent = trusted ? "\r" : ""
    }

    @objc private func requestAccess() {
        /* The system prompt appears only on the very first ask; afterwards
           macOS stays silent, so the settings link below is the fallback. */
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func openSystemSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security"
                    + "?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func start() {
        guard AXIsProcessTrusted() else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        window?.delegate = nil
        onComplete()
        close()
    }
}

/* One keyboard key, drawn as a keycap. */
private final class KeycapView: NSView {
    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.quaternarySystemFill.setFill()
        body.fill()
        NSColor.separatorColor.setStroke()
        body.lineWidth = 1
        body.stroke()

        let text = NSAttributedString(
            string: symbol,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
        let size = text.size()
        text.draw(
            at: NSPoint(
                x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/* A drawn "screenshot" of Oriel in action: a display with one window
   snapped to the left half and another mid-flight toward the right half.
   Drawn (not a bundled image) so it stays crisp at any backing scale and
   needs no resource plumbing. */
private final class OnboardingIllustrationView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let canvas = bounds

        // Desktop backdrop, in the app's blue
        let backdrop = NSBezierPath(roundedRect: canvas, xRadius: 12, yRadius: 12)
        NSGradient(
            starting: NSColor(srgbRed: 0.09, green: 0.17, blue: 0.31, alpha: 1),
            ending: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.17, alpha: 1)
        )?.draw(in: backdrop, angle: -90)

        // The display
        let display = NSRect(x: 60, y: 26, width: 360, height: 148)
        let screen = NSBezierPath(roundedRect: display, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.08).setFill()
        screen.fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        screen.lineWidth = 1.5
        screen.stroke()

        // Left half: a settled, snapped window
        drawWindow(
            NSRect(x: display.minX + 6, y: display.minY + 6,
                   width: display.width / 2 - 9, height: display.height - 12),
            emphasized: true)

        // Right half: the target zone the second window is snapping into
        let zone = NSRect(
            x: display.midX + 3, y: display.minY + 6,
            width: display.width / 2 - 9, height: display.height - 12)
        let dashes = NSBezierPath(roundedRect: zone, xRadius: 6, yRadius: 6)
        dashes.setLineDash([5, 4], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        dashes.lineWidth = 1.5
        dashes.stroke()

        // The window mid-flight, slightly overlapping the zone
        drawWindow(
            NSRect(x: display.midX + 26, y: display.minY + 30,
                   width: display.width / 2 - 44, height: display.height - 58),
            emphasized: false)
    }

    private func drawWindow(_ frame: NSRect, emphasized: Bool) {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)

        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        let body = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        (emphasized
            ? NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)
            : NSColor(srgbRed: 0.87, green: 0.9, blue: 0.94, alpha: 1)).setFill()
        body.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        for (index, tint) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            let dot = NSRect(
                x: frame.minX + 9 + CGFloat(index) * 11, y: frame.maxY - 13,
                width: 6, height: 6)
            tint.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        // Ghost content lines
        NSColor.black.withAlphaComponent(0.12).setFill()
        for row in 0..<2 {
            let bar = NSRect(
                x: frame.minX + 10, y: frame.maxY - 32 - CGFloat(row) * 12,
                width: frame.width * (row == 0 ? 0.5 : 0.34), height: 5)
            NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
        }
    }
}
