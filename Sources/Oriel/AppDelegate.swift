import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private let hotKeys = HotKeyCenter()
    private let shortcutStore = ShortcutStore()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureAccessibilityPermission()
        applyShortcuts()
        observeShortcutChanges()
        observePreferenceChanges()
        updateStatusItemVisibility()

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    /* Launching the app again while it's already running sends "reopen" to
       the live instance. With the menu bar icon hidden this is the only way
       back into the UI, so surface Settings (which also puts the app in the
       Dock via updateActivationPolicy). */
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if AppPreferences.isMenuBarIconHidden {
            openSettings()
        }
        return false
    }

    private func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            NSLog(
                "Oriel: waiting for Accessibility permission. "
                    + "Grant it in System Settings > Privacy & Security > Accessibility, "
                    + "then trigger any shortcut again."
            )
        }
    }

    private func applyShortcuts() {
        hotKeys.unregisterAll()
        for action in ShortcutAction.allCases {
            let spec = shortcutStore.spec(for: action)
            hotKeys.register(keyCode: spec.keyCode, modifiers: spec.carbonModifiers) {
                [weak self] in
                self?.perform(action)
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleMaximize: windowManager.toggleMaximize()
        case .nextDisplay: windowManager.moveToAdjacentDisplay(step: 1)
        case .previousDisplay: windowManager.moveToAdjacentDisplay(step: -1)
        case .leftHalf: windowManager.moveToHalf(.left)
        case .rightHalf: windowManager.moveToHalf(.right)
        }
    }

    private func observeShortcutChanges() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: ShortcutStore.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyShortcuts()
        }
        center.addObserver(
            forName: .shortcutRecordingBegan, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotKeys.unregisterAll()
        }
        center.addObserver(
            forName: .shortcutRecordingEnded, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyShortcuts()
        }
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateStatusItemVisibility()
        }
    }

    private func updateStatusItemVisibility() {
        if AppPreferences.isMenuBarIconHidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        } else if statusItem == nil {
            setUpStatusItem()
        }
        updateActivationPolicy()
    }

    private var isSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    /* Dock presence: the app normally stays invisible (accessory policy),
       but while the menu bar icon is hidden AND Settings is open there would
       be no sign the app is running — so it joins the Dock for the duration
       and leaves again when the settings window closes. */
    private func updateActivationPolicy() {
        let wantsDock = AppPreferences.isMenuBarIconHidden && isSettingsWindowVisible
        let policy: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        /* Flipping the policy can drop activation; keep Settings in front. */
        if isSettingsWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Oriel"
        )

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Oriel", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: shortcutStore)
            if let window = settingsWindowController?.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak self] _ in
                    /* isVisible is still true inside willClose; re-evaluate
                       (and leave the Dock) on the next runloop cycle. */
                    DispatchQueue.main.async { self?.updateActivationPolicy() }
                }
            }
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
