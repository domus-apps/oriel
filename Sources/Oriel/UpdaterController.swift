import AppKit
import Sparkle

/* Sparkle auto-update, isolated in this file so a future App Store variant
   (which must not ship a self-updater, guideline 2.5.2) can compile it out
   wholesale along with the Sparkle dependency. */
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    /* Sparkle only holds its delegate weakly. */
    private let relaunchMarker = RelaunchMarker()
    private let isStarted: Bool

    init() {
        /* `swift run` (non-bundled dev builds) has no Info.plist, so Sparkle
           has no feed URL or public key there — don't start the updater, or
           it just logs errors. The menu item stays disabled via Sparkle's
           own menu validation. */
        isStarted = Bundle.main.bundleIdentifier != nil
        controller = SPUStandardUpdaterController(
            startingUpdater: isStarted, updaterDelegate: relaunchMarker, userDriverDelegate: nil)
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: "")
        item.target = controller
        return item
    }

    /* Unlike menu items, buttons aren't auto-validated, so disable manually
       when the updater never started (non-bundled dev builds). */
    func makeCheckButton() -> NSButton {
        let button = NSButton(
            title: "Check for Updates…", target: controller,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        button.isEnabled = isStarted
        return button
    }

    fileprivate static let relaunchKey = "update.relaunchedAt"

    /* Sparkle relaunching the app after installing an update isn't someone
       opening it. Reads (and clears) the note left just before. */
    static func launchedByUpdate() -> Bool {
        let defaults = UserDefaults.standard
        guard let relaunchedAt = defaults.object(forKey: relaunchKey) as? Date else {
            return false
        }
        defaults.removeObject(forKey: relaunchKey)
        return Date().timeIntervalSince(relaunchedAt) < 10 * 60
    }
}

private final class RelaunchMarker: NSObject, SPUUpdaterDelegate {
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        UserDefaults.standard.set(Date(), forKey: UpdaterController.relaunchKey)
    }
}
