import AppKit

final class WindowManager {
    enum Half {
        case left, right
    }

    /* Frames saved by toggleMaximize, matched by AX element identity
       (CFEqual) so each window restores to its own previous frame. Kept as
       an array because AXUIElement is not Hashable in Swift. */
    private var savedFrames: [(window: AccessibilityWindow, frame: CGRect)] = []

    // MARK: Maximize / restore

    func toggleMaximize() {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard !screens.isEmpty else { return }
        let screen = screens[ScreenMath.screenIndex(containing: frame, in: screens)]

        if isApproximately(frame, screen),
            let savedIndex = savedFrames.firstIndex(where: { $0.window.isSameWindow(as: window) })
        {
            let saved = savedFrames.remove(at: savedIndex)
            window.setFrame(saved.frame)
        } else {
            savedFrames.removeAll { $0.window.isSameWindow(as: window) }
            savedFrames.append((window, frame))
            if savedFrames.count > 32 { savedFrames.removeFirst() }
            window.setFrame(screen)
        }
    }

    // MARK: Move across displays, preserving relative position and size

    func moveToAdjacentDisplay(step: Int) {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard screens.count > 1 else { return }

        let currentIndex = ScreenMath.screenIndex(containing: frame, in: screens)
        let count = screens.count
        let targetIndex = ((currentIndex + step) % count + count) % count

        let newFrame = ScreenMath.relativeReposition(
            windowFrame: frame,
            from: screens[currentIndex],
            to: screens[targetIndex]
        )
        window.setFrame(newFrame)
    }

    // MARK: Halves

    func moveToHalf(_ half: Half) {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard !screens.isEmpty else { return }
        let screen = screens[ScreenMath.screenIndex(containing: frame, in: screens)]

        let width = (screen.width / 2).rounded(.down)
        let origin: CGPoint =
            switch half {
            case .left: CGPoint(x: screen.minX, y: screen.minY)
            case .right: CGPoint(x: screen.maxX - width, y: screen.minY)
            }
        window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: screen.height)))
    }

    /* Some apps refuse the exact requested frame by a few points (size
       constraints, integral rounding), so "already maximized" needs slack. */
    private func isApproximately(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
