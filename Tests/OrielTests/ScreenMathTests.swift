import CoreGraphics
import Testing

@testable import Oriel

/* A 4K-ish source and a laptop-ish target, both already in AX space. */
private let source = CGRect(x: 0, y: 0, width: 3840, height: 2160)
private let target = CGRect(x: 3840, y: 0, width: 1512, height: 945)

@Test func centeredWindowLandsCentered() {
    let window = CGRect(x: (3840 - 800) / 2, y: (2160 - 600) / 2, width: 800, height: 600)
    let moved = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)

    #expect(moved.size == window.size)
    #expect(abs(moved.midX - target.midX) < 0.5)
    #expect(abs(moved.midY - target.midY) < 0.5)
}

@Test func edgeFlushWindowStaysFlush() {
    let topLeft = CGRect(x: 0, y: 0, width: 800, height: 600)
    let movedTopLeft = ScreenMath.relativeReposition(windowFrame: topLeft, from: source, to: target)
    #expect(movedTopLeft.minX == target.minX)
    #expect(movedTopLeft.minY == target.minY)

    let bottomRight = CGRect(x: 3840 - 800, y: 2160 - 600, width: 800, height: 600)
    let movedBottomRight = ScreenMath.relativeReposition(
        windowFrame: bottomRight, from: source, to: target)
    #expect(movedBottomRight.maxX == target.maxX)
    #expect(movedBottomRight.maxY == target.maxY)
}

@Test func sizeIsPreservedWhenItFits() {
    let window = CGRect(x: 1000, y: 500, width: 1200, height: 800)
    let moved = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)
    #expect(moved.size == window.size)
    #expect(target.contains(moved))
}

@Test func oversizedWindowShrinksToTarget() {
    let window = CGRect(x: 100, y: 100, width: 3000, height: 1800)
    let moved = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)
    #expect(moved.width == target.width)
    #expect(moved.height == target.height)
    #expect(target.contains(moved))
}

@Test func windowFillingSourceAxisCentersOnTarget() {
    let window = CGRect(x: 0, y: 700, width: 3840, height: 600)
    let moved = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)
    #expect(moved.width == target.width)
    #expect(abs(moved.midX - target.midX) < 0.5)
}

@Test func partiallyOffscreenWindowClampsInsideTarget() {
    let window = CGRect(x: -200, y: -100, width: 800, height: 600)
    let moved = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)
    #expect(target.contains(moved))
    #expect(moved.minX == target.minX)
    #expect(moved.minY == target.minY)
}

@Test func roundTripReturnsToOriginalPosition() {
    let window = CGRect(x: 900, y: 300, width: 1000, height: 700)
    let there = ScreenMath.relativeReposition(windowFrame: window, from: source, to: target)
    let back = ScreenMath.relativeReposition(windowFrame: there, from: target, to: source)
    #expect(abs(back.minX - window.minX) < 1)
    #expect(abs(back.minY - window.minY) < 1)
    #expect(back.size == window.size)
}
