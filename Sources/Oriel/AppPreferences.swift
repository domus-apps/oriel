import Foundation

/* App-level preferences (not shortcuts — those live in ShortcutStore).
   Same UserDefaults caveat as ShortcutStore: `swift run` and the bundled app
   use different defaults domains. */
enum AppPreferences {
    static let changed = Notification.Name("Oriel.PreferencesChanged")

    private static let hideMenuBarIconKey = "pref.hideMenuBarIcon"

    static var isMenuBarIconHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hideMenuBarIconKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideMenuBarIconKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}
