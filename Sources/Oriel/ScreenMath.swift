import AppKit

/* All window math in this app happens in the Accessibility API's coordinate
   space: origin at the TOP-LEFT of the primary screen, y grows downward.
   NSScreen frames use Cocoa's bottom-left-origin space, so every NSScreen
   rect must pass through `flipped(_:)` before being compared with an AX
   window frame. */
enum ScreenMath {
    /* The primary screen is the one whose Cocoa frame origin is (0, 0) —
       NSScreen.main is the screen with keyboard focus, which is not the
       same thing. */
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    /* Cocoa rect (bottom-left origin) → AX rect (top-left origin).
       The transform is its own inverse for rects of equal height. */
    static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /* Screens ordered left-to-right, with their usable areas (menu bar and
       Dock excluded) already flipped into AX space. */
    static func orderedVisibleFrames() -> [CGRect] {
        NSScreen.screens
            .sorted { $0.frame.minX < $1.frame.minX }
            .map { flipped($0.visibleFrame) }
    }

    /* Index of the screen a window belongs to: largest overlap wins, and a
       fully offscreen window falls back to the nearest screen center. */
    static func screenIndex(containing windowFrame: CGRect, in screens: [CGRect]) -> Int {
        let overlaps = screens.map { screen -> CGFloat in
            let i = screen.intersection(windowFrame)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = overlaps.enumerated().max(by: { $0.element < $1.element }),
            best.element > 0
        {
            return best.offset
        }
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screens.enumerated().min { a, b in
            hypot(a.element.midX - center.x, a.element.midY - center.y)
                < hypot(b.element.midX - center.x, b.element.midY - center.y)
        }?.offset ?? 0
    }

    /* The core feature: keep the window the same size and place it at the
       same relative position on the target screen. "Relative" is normalized
       against the FREE space (screen minus window), not the full screen —
       full-screen ratios drift because the window keeps its size while the
       screen changes: a centered window would land off-center and an
       edge-flush window would detach from the edge. Free-space ratios map
       center → center and flush edge → flush edge exactly. */
    static func relativeReposition(
        windowFrame: CGRect,
        from source: CGRect,
        to target: CGRect
    ) -> CGRect {
        var size = windowFrame.size
        size.width = min(size.width, target.width)
        size.height = min(size.height, target.height)

        /* A window partially offscreen yields a ratio outside 0...1; clamp
           so it lands inside the target. A window filling the source axis
           has no free space — center it on that axis. */
        func ratio(_ windowMin: CGFloat, _ screenMin: CGFloat, _ free: CGFloat) -> CGFloat {
            guard free > 0 else { return 0.5 }
            return min(max((windowMin - screenMin) / free, 0), 1)
        }
        let relX = ratio(windowFrame.minX, source.minX, source.width - windowFrame.width)
        let relY = ratio(windowFrame.minY, source.minY, source.height - windowFrame.height)

        let origin = CGPoint(
            x: target.minX + relX * max(target.width - size.width, 0),
            y: target.minY + relY * max(target.height - size.height, 0)
        )
        return CGRect(origin: origin, size: size)
    }

    /* Snapped states are the exception to the keep-size rule: a window
       occupying a half or the whole of its screen is proportional by
       intent, so a display move re-creates the same snap on the target
       screen instead of carrying the source screen's absolute size over. */
    enum Snap: CaseIterable {
        case leftHalf, rightHalf, maximized
    }

    static func snapFrame(_ snap: Snap, on screen: CGRect) -> CGRect {
        switch snap {
        case .maximized:
            return screen
        case .leftHalf, .rightHalf:
            let width = (screen.width / 2).rounded(.down)
            let x = snap == .leftHalf ? screen.minX : screen.maxX - width
            return CGRect(x: x, y: screen.minY, width: width, height: screen.height)
        }
    }

    /* Detection is geometric, not action history: a window still sitting
       where a snap would put it counts, whoever put it there. */
    static func detectedSnap(
        of windowFrame: CGRect, on screen: CGRect, tolerance: CGFloat = 8
    ) -> Snap? {
        Snap.allCases.first {
            approximatelyEqual(snapFrame($0, on: screen), windowFrame, tolerance: tolerance)
        }
    }

    /* Some apps refuse the exact requested frame by a few points (size
       constraints, integral rounding), so frame comparisons need slack. */
    static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /* Center the window on its screen, keeping its size — shrunk only if
       it's larger than the screen, matching the display-move rule. */
    static func centered(windowFrame: CGRect, in screen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(windowFrame.width, screen.width),
            height: min(windowFrame.height, screen.height)
        )
        let origin = CGPoint(
            x: (screen.minX + (screen.width - size.width) / 2).rounded(),
            y: (screen.minY + (screen.height - size.height) / 2).rounded()
        )
        return CGRect(origin: origin, size: size)
    }
}
