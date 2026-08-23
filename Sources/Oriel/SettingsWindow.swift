import AppKit
import Carbon.HIToolbox
import ServiceManagement

extension Notification.Name {
    /* Recording captures key events locally, so the app must drop its global
       hotkeys for the duration — otherwise pressing a currently-registered
       combination triggers the action instead of recording it. */
    static let shortcutRecordingBegan = Notification.Name("Oriel.RecordingBegan")
    static let shortcutRecordingEnded = Notification.Name("Oriel.RecordingEnded")
}

// MARK: - Window

enum SettingsPane: Int, CaseIterable {
    case general
    case shortcuts

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        }
    }
}

/* System Settings-style window: full-height sidebar on the left, panes on
   the right. The style mask keeps all three traffic lights live (zoom stays
   disabled by macOS itself while the window is not resizable-by-content,
   matching native settings windows). */
final class SettingsWindowController: NSWindowController {
    private let splitViewController: SettingsSplitViewController

    init(store: ShortcutStore) {
        splitViewController = SettingsSplitViewController(store: store)

        let window = NSWindow(contentViewController: splitViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        /* A toolbar (even an empty one) is required for the full-height
           sidebar look; unifiedCompact keeps its title bar at roughly
           standard height instead of the tall unified variant. */
        window.toolbarStyle = .unifiedCompact
        window.toolbar = NSToolbar()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 640, height: 380))
        window.center()

        super.init(window: window)
        splitViewController.onPaneChange = { [weak window] pane in
            window?.title = pane.title
        }
        splitViewController.show(.general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class SettingsSplitViewController: NSSplitViewController {
    var onPaneChange: ((SettingsPane) -> Void)?

    private let sidebar = SettingsSidebarViewController()
    private let paneContainer = NSViewController()
    private let generalPane = GeneralPaneViewController()
    private let shortcutsPane: ShortcutsPaneViewController
    private var currentPane: NSViewController?

    init(store: ShortcutStore) {
        shortcutsPane = ShortcutsPaneViewController(store: store)
        super.init(nibName: nil, bundle: nil)

        paneContainer.view = NSView()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 160
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: paneContainer))

        sidebar.onSelect = { [weak self] pane in
            self?.show(pane)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ pane: SettingsPane) {
        let next: NSViewController =
            switch pane {
            case .general: generalPane
            case .shortcuts: shortcutsPane
            }
        guard next !== currentPane else { return }

        if let currentPane {
            currentPane.view.removeFromSuperview()
            currentPane.removeFromParent()
        }
        paneContainer.addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.view.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.topAnchor.constraint(equalTo: paneContainer.view.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: paneContainer.view.bottomAnchor),
            next.view.leadingAnchor.constraint(equalTo: paneContainer.view.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: paneContainer.view.trailingAnchor),
        ])
        currentPane = next

        sidebar.select(pane)
        onPaneChange?(pane)
    }
}

// MARK: - Sidebar

final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate
{
    var onSelect: ((SettingsPane) -> Void)?

    private let tableView = NSTableView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowSizeStyle = .default
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        view = scrollView
    }

    func select(_ pane: SettingsPane) {
        guard tableView.selectedRow != pane.rawValue else { return }
        tableView.selectRowIndexes(IndexSet(integer: pane.rawValue), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsPane.allCases.count
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard let pane = SettingsPane(rawValue: row) else { return nil }

        let cell = NSTableCellView()
        let imageView = NSImageView(
            image: NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
                ?? NSImage())
        let textField = NSTextField(labelWithString: pane.title)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let pane = SettingsPane(rawValue: tableView.selectedRow) else { return }
        onSelect?(pane)
    }
}

// MARK: - General pane

final class GeneralPaneViewController: NSViewController {
    private lazy var launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Launch at login", target: self,
        action: #selector(toggleLaunchAtLogin))

    private lazy var hideMenuBarIconCheckbox = NSButton(
        checkboxWithTitle: "Hide menu bar icon", target: self,
        action: #selector(toggleHideMenuBarIcon))

    /* SMAppService needs a real app bundle; a bare `swift run` binary has no
       bundle identifier to register. */
    private var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    override func loadView() {
        var views: [NSView] = [launchAtLoginCheckbox]
        if isBundledApp {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginCheckbox.isEnabled = false
            let note = NSTextField(
                wrappingLabelWithString:
                    "Available in the bundled app only (Scripts/bundle.sh).")
            note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            note.textColor = .secondaryLabelColor
            views.append(note)
        }

        hideMenuBarIconCheckbox.state = AppPreferences.isMenuBarIconHidden ? .on : .off
        views.append(hideMenuBarIconCheckbox)
        let hideNote = NSTextField(
            wrappingLabelWithString:
                "While hidden, launch Oriel again to open Settings. "
                + "The app appears in the Dock only while this window is open.")
        hideNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hideNote.textColor = .secondaryLabelColor
        views.append(hideNote)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        view = container
    }

    @objc private func toggleHideMenuBarIcon() {
        AppPreferences.isMenuBarIconHidden = hideMenuBarIconCheckbox.state == .on
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginCheckbox.state = launchAtLoginCheckbox.state == .on ? .off : .on
            NSLog("Oriel: launch-at-login change failed: \(error)")
        }
    }
}

// MARK: - Shortcuts pane

final class ShortcutsPaneViewController: NSViewController {
    private let store: ShortcutStore
    private var recorderButtons: [ShortcutAction: ShortcutRecorderButton] = [:]

    init(store: ShortcutStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 16

        for action in ShortcutAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            let button = ShortcutRecorderButton(spec: store.spec(for: action))
            button.onChange = { [store] spec in
                store.set(spec, for: action)
            }
            recorderButtons[action] = button
            grid.addRow(with: [label, button])
        }
        grid.column(at: 0).xPlacement = .trailing

        let resetButton = NSButton(
            title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))

        let stack = NSStackView(views: [grid, resetButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
        ])
        view = container
    }

    @objc private func resetToDefaults() {
        store.resetAll()
        for (action, button) in recorderButtons {
            button.spec = store.spec(for: action)
        }
    }
}

// MARK: - Recorder button

/* Click to record: the button captures the next key press with a local event
   monitor. Esc cancels; combinations without ⌘/⌃/⌥ are rejected so plain
   typing can't become a global shortcut. */
final class ShortcutRecorderButton: NSButton {
    var spec: ShortcutSpec {
        didSet { title = spec.displayString }
    }
    var onChange: ((ShortcutSpec) -> Void)?

    private var eventMonitor: Any?
    private var isRecording = false

    init(spec: ShortcutSpec) {
        self.spec = spec
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        title = spec.displayString
        target = self
        action = #selector(toggleRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func toggleRecording() {
        isRecording ? finishRecording(with: nil) : beginRecording()
    }

    private func beginRecording() {
        isRecording = true
        title = "Type shortcut…"
        NotificationCenter.default.post(name: .shortcutRecordingBegan, object: self)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.finishRecording(with: nil)
                return nil
            }
            let modifiers = ShortcutSpec.carbonModifiers(from: event.modifierFlags)
            let required = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
            guard modifiers & required != 0 else {
                NSSound.beep()
                return nil
            }
            self.finishRecording(
                with: ShortcutSpec(
                    keyCode: UInt32(event.keyCode),
                    carbonModifiers: modifiers,
                    keyLabel: ShortcutSpec.keyLabel(for: event)
                ))
            return nil
        }
    }

    private func finishRecording(with newSpec: ShortcutSpec?) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        if let newSpec {
            spec = newSpec
            onChange?(newSpec)
        } else {
            title = spec.displayString
        }
        NotificationCenter.default.post(name: .shortcutRecordingEnded, object: self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isRecording {
            finishRecording(with: nil)
        }
    }
}
