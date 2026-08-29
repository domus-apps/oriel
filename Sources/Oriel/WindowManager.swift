import AppKit

final class WindowManager {
    enum Half {
        case left, right
    }

    /* Per-window restore state, matched by AX element identity (CFEqual) so
       each window restores to its own previous frame. Kept as an array
       because AXUIElement is not Hashable in Swift.

       restoreFrame is the frame the window had before Oriel first touched
       it; lastAppliedFrame is the frame the window actually ended up with
       after Oriel's last action (read back, since apps can refuse or clamp
       the requested frame). Chained actions (left half → right half →
       maximize) keep the original restoreFrame as long as the user hasn't
       rearranged the window in between, so Restore always returns to the
       user's own arrangement, not an intermediate Oriel-set one.

       Display moves are deliberately not part of that chain: they start a
       new one, with the landing spot on the target display as the restore
       point — restoring after "next display → right half" should return to
       where the window landed on that display, not yank it back across
       displays. */
    private struct History {
        let window: AccessibilityWindow
        var restoreFrame: CGRect
        var lastAppliedFrame: CGRect
    }

    private var histories: [History] = []

    // MARK: Restore

    func restorePreviousFrame() {
        guard let window = AccessibilityWindow.focused() else { return }
        guard let index = histories.firstIndex(where: { $0.window.isSameWindow(as: window) })
        else { return }
        let history = histories.remove(at: index)
        window.setFrame(history.restoreFrame)
    }

    // MARK: Maximize / restore

    func toggleMaximize() {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard !screens.isEmpty else { return }
        let screen = screens[ScreenMath.screenIndex(containing: frame, in: screens)]

        if isApproximately(frame, screen),
            histories.contains(where: { $0.window.isSameWindow(as: window) })
        {
            restorePreviousFrame()
        } else {
            apply(screen, to: window, currentFrame: frame)
        }
    }

    // MARK: Move across displays — snapped windows re-snap on the target,
    // everything else keeps its size and relative position

    func moveToAdjacentDisplay(step: Int) {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard screens.count > 1 else { return }

        let currentIndex = ScreenMath.screenIndex(containing: frame, in: screens)
        let count = screens.count
        let targetIndex = ((currentIndex + step) % count + count) % count
        let source = screens[currentIndex]
        let target = screens[targetIndex]

        let snap = ScreenMath.detectedSnap(of: frame, on: source)
        let newFrame =
            snap.map { ScreenMath.snapFrame($0, on: target) }
            ?? ScreenMath.relativeReposition(windowFrame: frame, from: source, to: target)
        apply(
            newFrame, to: window, currentFrame: frame,
            alignTrailing: snap == .rightHalf, resetsRestorePoint: true)
    }

    // MARK: Halves

    func moveToHalf(_ half: Half) {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard !screens.isEmpty else { return }
        let screen = screens[ScreenMath.screenIndex(containing: frame, in: screens)]

        apply(
            ScreenMath.snapFrame(half == .left ? .leftHalf : .rightHalf, on: screen),
            to: window, currentFrame: frame,
            /* A window that refuses the half width would otherwise be left
               hanging at the target origin — mid-screen for the right half —
               so re-anchor it to the edge the action aimed for. */
            alignTrailing: half == .right)
    }

    // MARK: Center

    func center() {
        guard let window = AccessibilityWindow.focused(), let frame = window.frame else { return }
        let screens = ScreenMath.orderedVisibleFrames()
        guard !screens.isEmpty else { return }
        let screen = screens[ScreenMath.screenIndex(containing: frame, in: screens)]
        apply(ScreenMath.centered(windowFrame: frame, in: screen), to: window, currentFrame: frame)
    }

    // MARK: History

    private func apply(
        _ target: CGRect, to window: AccessibilityWindow, currentFrame: CGRect,
        alignTrailing: Bool = false, resetsRestorePoint: Bool = false
    ) {
        if alignTrailing {
            window.setFrameAnchoredTrailing(target)
        } else {
            window.setFrame(target)
        }

        /* Read back what the window actually accepted — apps refuse or clamp
           frames (fixed sizes, minimums, character-grid increments). */
        let applied = window.frame ?? target

        /* Track the applied (not requested) frame: comparing the next
           action's current frame against a frame the window never actually
           had would look like a user rearrangement and wrongly reset the
           restore point. */
        let restorePoint = resetsRestorePoint ? applied : currentFrame
        if let index = histories.firstIndex(where: { $0.window.isSameWindow(as: window) }) {
            if resetsRestorePoint
                || !isApproximately(currentFrame, histories[index].lastAppliedFrame)
            {
                /* Either this action starts a new chain (display move), or
                   the user rearranged the window since our last action —
                   both establish a new restore point. */
                histories[index].restoreFrame = restorePoint
            }
            histories[index].lastAppliedFrame = applied
        } else {
            histories.append(
                History(window: window, restoreFrame: restorePoint, lastAppliedFrame: applied))
            if histories.count > 32 { histories.removeFirst() }
        }
    }

    private func isApproximately(_ a: CGRect, _ b: CGRect) -> Bool {
        ScreenMath.approximatelyEqual(a, b)
    }
}
