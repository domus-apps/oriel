import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windowManager = WindowManager()
    private let hotKeys = HotKeyCenter()
    private let shortcutStore = ShortcutStore()
    private let updater = UpdaterController()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?

    private static let onboardingCompletedKey = "onboarding.completed"

    func applicationDidFinishLaunching(_ notification: Notification) {
        /* A translocated launch relaunches itself from the real bundle —
           nothing else must start in this doomed instance. */
        if TranslocationHealer.healIfNeeded() { return }

        setUpMainMenu()
        applyShortcuts()
        observeShortcutChanges()
        observePreferenceChanges()
        updateStatusItemVisibility()

        /* The Accessibility ask lives inside onboarding — no launch-time
           prompt. Completion is only recorded when onboarding is finished
           properly, so an interrupted (or force-quit) run shows it again. */
        if !UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
            || CommandLine.arguments.contains("--onboarding")
        {
            showOnboarding()
        }

        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    private func showOnboarding() {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
                self?.onboardingController = nil
            }
            observeClose(of: onboardingController?.window)
        }
        comeForward()
        onboardingController?.window?.makeKeyAndOrderFront(nil)
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

    /* An accessory app has no visible menu bar, but ⌘-key equivalents are
       still dispatched through the main menu — without one, ⌘W/⌘Q do
       nothing in the settings window. The menu also becomes visible for
       real whenever the app temporarily joins the Dock (regular policy). */
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(updater.makeMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Oriel",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            NSMenuItem(
                title: "Close Window",
                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
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
        case .center: windowManager.center()
        case .restore: windowManager.restorePreviousFrame()
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

    /* Activation hand-back. An accessory app that activates itself to show
       a window stays the active app after that window closes — macOS never
       moves activation on window close — so a windowless Oriel was left
       frontmost until the user clicked elsewhere. Anything keyed off the
       frontmost app then misbehaves (Atrium's Option+` lists the front app's
       windows and found none; plain keys beep). Remember who was active
       before we came forward and give activation back once our last window
       is gone. */
    private var previouslyActiveApp: NSRunningApplication?

    private func comeForward() {
        if !NSApp.isActive,
            let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            previouslyActiveApp = front
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handBackActivationIfWindowless() {
        guard NSApp.isActive, !isSettingsWindowVisible,
            onboardingController?.window?.isVisible != true
        else { return }
        let previous = previouslyActiveApp
        previouslyActiveApp = nil
        if let previous, !previous.isTerminated,
            previous.activate(from: .current, options: [])
        {
            return
        }
        /* No one to hand back to (quit meanwhile): hiding yields activation
           to whatever the system picks next. */
        NSApp.hide(nil)
    }

    private func observeClose(of window: NSWindow?) {
        guard let window else { return }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            /* isVisible is still true inside willClose; re-evaluate (leave
               the Dock, hand activation back) on the next runloop cycle. */
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
                self?.handBackActivationIfWindowless()
            }
        }
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
        /* Flipping the policy can drop activation; keep Settings in front.
           Going back to accessory has to wait: macOS 27.2 (measured
           2026-09-18) leaves the window undraggable by its title bar until
           the app goes through a real activation, and the deactivation the
           flip causes lands asynchronously — re-activating right away (even
           on the next run-loop turn or on didResignActive, ~10 ms) is a
           no-op that leaves the window stuck; 50 ms was borderline, 0.2 s
           and up always worked. Going to regular has no such problem. */
        guard isSettingsWindowVisible else { return }
        if policy == .regular {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, isSettingsWindowVisible else { return }
                NSApp.activate(ignoringOtherApps: true)
                settingsWindowController?.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func setUpStatusItem() {
        /* A fixed length instead of squareLength: square items are as wide
           as the menu bar is tall, which pads a ~18pt symbol with a lot of
           dead space. 20pt hugs the icon while keeping its natural size. */
        let item = NSStatusBar.system.statusItem(withLength: 20)
        item.button?.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Oriel"
        )

        let menu = NSMenu()
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let about = NSMenuItem(title: "Oriel \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(updater.makeMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Oriel", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                store: shortcutStore, updater: updater)
            observeClose(of: settingsWindowController?.window)
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        comeForward()
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
