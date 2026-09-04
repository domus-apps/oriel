# Changelog

All notable changes to Oriel are documented here. The release workflow publishes each version's section as the GitHub release notes and embeds it in the Sparkle appcast, so the in-app update dialog shows the same notes. A release fails early if its version has no section here.

Keep each bullet on a single line: release notes render line breaks literally (both on GitHub and in the update dialog), so wrapped lines would break mid-sentence.

## 1.3.1

### Added

- Spotlight now finds the app by its Korean name and by what it does: 오리엘, 오리얼, 창 관리, and window manager all match.

## 1.3.0

### Changed

- Moving a snapped window (left/right half or maximized) to another display now re-creates the same snap on the target display, instead of carrying the source display's absolute size over. Detection is geometric, so it applies to any window sitting in a snap position, whoever put it there.

## 1.2.1

- Fixed: installing by COPYING the app (instead of Finder-moving it) left it running from Gatekeeper's translocated read-only path, which blocked Sparkle updates. The app now detects this at launch, clears the quarantine flag, and relaunches itself from its real location.

## 1.2.0

### Added

- A Center action (⌃⌥C by default) that centers the focused window on its display, customizable like every other shortcut.
- First-run onboarding that explains the app and hosts the Accessibility permission ask. The launch-time system prompt is gone.

### Changed

- The status menu shows the app version at the top.

## 1.1.0

### Fixed

- Windows that refuse horizontal resizing (fixed-width windows) now snap flush to the display's right edge instead of stopping at mid-screen, and without flickering through an intermediate position.
- Restore now returns to the window's position from before the whole chain of snap/maximize actions, not just the most recent one, including for windows that clamp their size.

### Changed

- Moving a window to another display starts a new restore chain: pressing Restore afterwards returns the window to where it landed on that display instead of yanking it back across displays.

## 1.0.0

- Initial release: snap windows to left/right halves, toggle maximize, move windows across displays keeping their relative position, restore, and configurable global shortcuts.
- Menu bar app with a hideable icon, launch at login, and Sparkle auto-updates.
