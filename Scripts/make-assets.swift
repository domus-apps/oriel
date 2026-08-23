#!/usr/bin/env swift
// Generates the app icon (Assets/AppIcon.iconset/*.png + icon-1024.png) and
// the README banner (Assets/banner.png) programmatically, so the artwork is
// reproducible from source. Run: swift Scripts/make-assets.swift
// Then:  iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
//
// Styled after macOS Tahoe's Liquid Glass icon language: a continuous-curvature
// squircle, a frosted-glass window panel (real gaussian-blurred backdrop via
// CoreImage), specular rim highlights, and soft layered shadows.

import AppKit
import CoreImage

// MARK: - Helpers

let ciContext = CIContext()

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func withContext(_ rep: NSBitmapImageRep, _ draw: (CGContext) -> Void) {
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.current = nil
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let rgb = CGColorSpaceCreateDeviceRGB()

func linearGradient(_ cg: CGContext, in path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let grad = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: nil)!
    cg.drawLinearGradient(grad, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()
}

func radialBlob(_ cg: CGContext, center: CGPoint, radius: CGFloat, color c: CGColor) {
    let grad = CGGradient(colorsSpace: rgb, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Continuous-curvature squircle (superellipse), the Apple icon silhouette.
func squircle(in rect: CGRect, exponent n: CGFloat = 4.6) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = rect.midX + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = rect.midY + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func gaussianBlur(_ image: CGImage, radius: CGFloat) -> CGImage {
    let ci = CIImage(cgImage: image)
    let blurred = ci.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        .cropped(to: ci.extent)
    return ciContext.createCGImage(blurred, from: ci.extent)!
}

// MARK: - Icon (designed in a 1024x1024 space, bottom-left origin)

let designRect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824) // standard macOS icon grid

/// Background layer: squircle, gradient, light blobs, top sheen, outer shadow.
func drawIconBackground(_ cg: CGContext) {
    let shape = squircle(in: bgRect)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 36, color: color(0x000000, 0.28))
    cg.addPath(shape)
    cg.setFillColor(color(0x2757D6))
    cg.fillPath()
    cg.restoreGState()

    // A single restrained azure gradient, in the language of macOS system
    // icons (Mail, App Store): the background recedes, the glyph is the hero.
    linearGradient(
        cg, in: shape,
        colors: [color(0x5AAEFF), color(0x1C66EC)],
        from: CGPoint(x: 512, y: bgRect.maxY), to: CGPoint(x: 512, y: bgRect.minY)
    )
    // Barely-there top light for depth
    linearGradient(
        cg, in: shape,
        colors: [color(0xFFFFFF, 0.1), color(0xFFFFFF, 0)],
        from: CGPoint(x: 512, y: bgRect.maxY), to: CGPoint(x: 512, y: bgRect.maxY - 320)
    )
}

/// Specular rim: a stroke around `path` that is bright on top, fading below.
func glassRim(_ cg: CGContext, around path: CGPath, width: CGFloat, bounds: CGRect, top: CGFloat, bottom: CGFloat) {
    let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    linearGradient(
        cg, in: stroked,
        colors: [color(0xFFFFFF, top), color(0xFFFFFF, bottom)],
        from: CGPoint(x: bounds.midX, y: bounds.maxY), to: CGPoint(x: bounds.midX, y: bounds.minY)
    )
}

/// One frosted-glass window pane: blurred backdrop, milky tint, specular rim.
func drawGlassPane(
    _ cg: CGContext, rect: CGRect, backdrop: CGImage,
    tintTop: CGFloat, tintBottom: CGFloat,
    rimWidth: CGFloat, rimTop: CGFloat, rimBottom: CGFloat,
    shadowBlur: CGFloat, shadowAlpha: CGFloat
) {
    let path = CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil)

    // Drop shadow (opaque fill, replaced by the glass interior right after)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -shadowBlur * 0.4), blur: shadowBlur, color: color(0x081B54, shadowAlpha))
    cg.addPath(path)
    cg.setFillColor(color(0x8FB4EE))
    cg.fillPath()
    cg.restoreGState()

    // Blurred backdrop + milky tint
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.draw(backdrop, in: designRect)
    linearGradient(
        cg, in: path,
        colors: [color(0xFFFFFF, tintTop), color(0xFFFFFF, tintBottom)],
        from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY)
    )
    cg.restoreGState()

    glassRim(cg, around: path, width: rimWidth, bounds: rect, top: rimTop, bottom: rimBottom)
}

// The glyph: a window mid-move — a ghost pane at the old position behind,
// the window itself arrived at the new position in front. Both panes sit
// well inside the squircle so the icon keeps clear breathing room.
let backPane = CGRect(x: 190, y: 460, width: 420, height: 330)
let frontPane = CGRect(x: 380, y: 230, width: 440, height: 340)

func drawBackPane(_ cg: CGContext, backdrop: CGImage, boost: Bool) {
    drawGlassPane(
        cg, rect: backPane, backdrop: backdrop,
        tintTop: boost ? 0.52 : 0.4, tintBottom: boost ? 0.4 : 0.26,
        rimWidth: 4, rimTop: 0.7, rimBottom: 0.12,
        shadowBlur: 30, shadowAlpha: 0.22
    )
}

func drawFrontPane(_ cg: CGContext, backdrop: CGImage, boost: Bool) {
    drawGlassPane(
        cg, rect: frontPane, backdrop: backdrop,
        tintTop: boost ? 0.98 : 0.94, tintBottom: boost ? 0.94 : 0.85,
        rimWidth: 5, rimTop: 1.0, rimBottom: 0.3,
        shadowBlur: 46, shadowAlpha: 0.32
    )

    drawWindowChrome(cg)
}

/// Traffic lights + content bars on the front pane. Shared between the
/// rendered icon and the flat Icon Composer layers.
func drawWindowChrome(_ cg: CGContext) {
    // Traffic lights — flat and native, like real macOS window controls: a
    // barely-there top-lit gradient and a darker hairline ring. No gloss.
    let dotY = frontPane.maxY - 52
    let lights: [(top: UInt32, base: UInt32, ring: UInt32)] = [
        (0xFF7B70, 0xFF5F57, 0xE2463D),
        (0xFFCF57, 0xFEBC2E, 0xDFA023),
        (0x4CD75C, 0x28C840, 0x1FA831),
    ]
    for (i, light) in lights.enumerated() {
        let x = frontPane.minX + 52 + CGFloat(i) * 50
        let dot = CGRect(x: x - 15, y: dotY - 15, width: 30, height: 30)
        linearGradient(
            cg, in: CGPath(ellipseIn: dot, transform: nil),
            colors: [color(light.top), color(light.base)],
            from: CGPoint(x: dot.midX, y: dot.maxY), to: CGPoint(x: dot.midX, y: dot.minY)
        )
        cg.addPath(CGPath(ellipseIn: dot.insetBy(dx: 1, dy: 1), transform: nil))
        cg.setStrokeColor(color(light.ring, 0.55))
        cg.setLineWidth(2)
        cg.strokePath()
    }

    // Ghosted content bars
    cg.setFillColor(color(0x4A7BE0, 0.3))
    for (i, w) in [CGFloat(210), 148].enumerated() {
        let y = frontPane.maxY - 148 - CGFloat(i) * 66
        let bar = CGRect(x: frontPane.minX + 52, y: y - 16, width: w, height: 32)
        cg.addPath(CGPath(roundedRect: bar, cornerWidth: 16, cornerHeight: 16, transform: nil))
    }
    cg.fillPath()
}

/// Renders the complete icon at `px` and returns the bitmap.
func makeIcon(px: Int) -> NSBitmapImageRep {
    let scale = CGFloat(px) / 1024
    let blurRadius = max(36 * scale, 1)
    // Small sizes: more opaque panes keep the glyph legible in the menu bar /
    // Dock, where the frosted subtlety would just vanish.
    let boost = px <= 64

    let bgRep = makeBitmap(px, px)
    withContext(bgRep) { cg in
        cg.scaleBy(x: scale, y: scale)
        drawIconBackground(cg)
    }
    let backdrop = gaussianBlur(bgRep.cgImage!, radius: blurRadius)

    // Intermediate scene (background + back pane), so the front pane's
    // backdrop blur includes the ghost pane behind it — glass over glass.
    let shape = squircle(in: bgRect)

    /* Clip the panes to the squircle, and at small sizes optically enlarge
       the glyph (like Apple's small-size icon variants) so it stays
       prominent in the menu bar / Dock. */
    func drawPanes(_ cg: CGContext, _ body: (CGContext) -> Void) {
        cg.saveGState()
        cg.addPath(shape)
        cg.clip()
        if boost {
            cg.translateBy(x: 512, y: 512)
            cg.scaleBy(x: 1.14, y: 1.14)
            cg.translateBy(x: -512, y: -512)
        }
        body(cg)
        cg.restoreGState()
    }

    let midRep = makeBitmap(px, px)
    withContext(midRep) { cg in
        cg.scaleBy(x: scale, y: scale)
        cg.draw(bgRep.cgImage!, in: designRect)
        drawPanes(cg) { drawBackPane($0, backdrop: backdrop, boost: boost) }
    }
    let midBackdrop = gaussianBlur(midRep.cgImage!, radius: blurRadius)

    let rep = makeBitmap(px, px)
    withContext(rep) { cg in
        cg.scaleBy(x: scale, y: scale)
        cg.draw(midRep.cgImage!, in: designRect)
        drawPanes(cg) { drawFrontPane($0, backdrop: midBackdrop, boost: boost) }
    }
    return rep
}

// MARK: - Icon Composer layers (macOS 26+ .icon document)

/* The .icon format gets dark/clear/tinted appearances for free: we ship flat
   transparent layers plus a background fill, and the system renders the
   Liquid Glass treatment (and the dark background) at runtime. In a .icon
   document the 1024pt canvas IS the icon shape — the system adds its own
   margins — whereas our design space puts the squircle at 100..924, so the
   panes are remapped to land at the same visual position. */
func makeIconLayer(_ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = makeBitmap(1024, 1024)
    withContext(rep) { cg in
        cg.scaleBy(x: 1024 / 824, y: 1024 / 824)
        cg.translateBy(x: -100, y: -100)
        draw(cg)
    }
    return rep
}

func drawFlatBackPane(_ cg: CGContext) {
    cg.addPath(CGPath(roundedRect: backPane, cornerWidth: 56, cornerHeight: 56, transform: nil))
    cg.setFillColor(color(0xFFFFFF, 0.4))
    cg.fillPath()
}

func drawFlatFrontPane(_ cg: CGContext) {
    cg.addPath(CGPath(roundedRect: frontPane, cornerWidth: 56, cornerHeight: 56, transform: nil))
    cg.setFillColor(color(0xFFFFFF))
    cg.fillPath()
    drawWindowChrome(cg)
}

// MARK: - Banner (1800 x 600)

func drawBanner(_ cg: CGContext, icon: CGImage) {
    let canvas = CGRect(x: 0, y: 0, width: 1800, height: 600)
    let frame = CGPath(roundedRect: canvas, cornerWidth: 40, cornerHeight: 40, transform: nil)
    linearGradient(
        cg, in: frame,
        colors: [color(0x14213F), color(0x0A1128)],
        from: CGPoint(x: canvas.midX, y: canvas.maxY), to: CGPoint(x: canvas.midX, y: canvas.minY)
    )

    // Faint decorative window outlines on the right
    cg.saveGState()
    cg.addPath(frame)
    cg.clip()
    cg.setStrokeColor(color(0xFFFFFF, 0.07))
    cg.setLineWidth(3)
    for (x, y, w, h) in [(1380.0, 250.0, 360.0, 260.0), (1520.0, 60.0, 420.0, 300.0), (1250.0, -80.0, 300.0, 220.0)] {
        cg.addPath(CGPath(
            roundedRect: CGRect(x: x, y: y, width: w, height: h),
            cornerWidth: 26, cornerHeight: 26, transform: nil
        ))
        cg.strokePath()
    }
    cg.restoreGState()

    // App icon on the left
    cg.draw(icon, in: CGRect(x: 100, y: 118, width: 364, height: 364))

    // Wordmark + tagline
    let title = NSAttributedString(string: "Oriel", attributes: [
        .font: NSFont.systemFont(ofSize: 130, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    title.draw(at: NSPoint(x: 520, y: 300))

    let tagline = NSAttributedString(string: "Keyboard-driven window management for macOS", attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.62, green: 0.71, blue: 0.88, alpha: 1),
    ])
    tagline.draw(at: NSPoint(x: 528, y: 218))

    // Shortcut keycaps
    var x: CGFloat = 528
    for key in ["⌃⌥↩", "⌃⌥⌘→", "⌃⌥←", "⌃⌥→"] {
        let label = NSAttributedString(string: key, attributes: [
            .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.78, green: 0.85, blue: 0.97, alpha: 1),
        ])
        let size = label.size()
        let pill = CGRect(x: x, y: 108, width: size.width + 48, height: 72)
        cg.addPath(CGPath(roundedRect: pill, cornerWidth: 18, cornerHeight: 18, transform: nil))
        cg.setFillColor(color(0xFFFFFF, 0.07))
        cg.fillPath()
        cg.addPath(CGPath(roundedRect: pill.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 17, cornerHeight: 17, transform: nil))
        cg.setStrokeColor(color(0xFFFFFF, 0.14))
        cg.setLineWidth(3)
        cg.strokePath()
        label.draw(at: NSPoint(x: pill.minX + 24, y: pill.minY + (pill.height - size.height) / 2))
        x = pill.maxX + 22
    }
}

// MARK: - GitHub social preview (1280 x 640 design space, rendered @2x)

func drawSocialPreview(_ cg: CGContext, icon: CGImage) {
    let canvas = CGRect(x: 0, y: 0, width: 1280, height: 640)
    // Full bleed — GitHub renders the preview edge to edge and rounds the
    // corners itself, so transparent corners would show through as white.
    linearGradient(
        cg, in: CGPath(rect: canvas, transform: nil),
        colors: [color(0x16244A), color(0x0A1128)],
        from: CGPoint(x: canvas.midX, y: canvas.maxY), to: CGPoint(x: canvas.midX, y: canvas.minY)
    )

    // Faint decorative window outlines drifting off the corners
    cg.saveGState()
    cg.setStrokeColor(color(0xFFFFFF, 0.06))
    cg.setLineWidth(2.5)
    for (x, y, w, h) in [
        (-90.0, 430.0, 300.0, 210.0), (60.0, 520.0, 260.0, 190.0),
        (1030.0, -60.0, 320.0, 230.0), (1140.0, 90.0, 280.0, 200.0),
    ] {
        cg.addPath(CGPath(
            roundedRect: CGRect(x: x, y: y, width: w, height: h),
            cornerWidth: 22, cornerHeight: 22, transform: nil
        ))
        cg.strokePath()
    }
    cg.restoreGState()

    func drawCentered(_ text: NSAttributedString, y: CGFloat) {
        text.draw(at: NSPoint(x: canvas.midX - text.size().width / 2, y: y))
    }

    // Centered stack: icon, wordmark, tagline, shortcut keycaps — sized up
    // so the card stays legible at the small sizes link previews render at.
    cg.draw(icon, in: CGRect(x: canvas.midX - 125, y: 355, width: 250, height: 250))

    drawCentered(
        NSAttributedString(string: "Oriel", attributes: [
            .font: NSFont.systemFont(ofSize: 100, weight: .bold),
            .foregroundColor: NSColor.white,
        ]), y: 238)

    drawCentered(
        NSAttributedString(string: "Keyboard-driven window management for macOS", attributes: [
            .font: NSFont.systemFont(ofSize: 38, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 0.62, green: 0.71, blue: 0.88, alpha: 1),
        ]), y: 176)

    let keys = ["⌃⌥↩", "⌃⌥←", "⌃⌥→", "⌃⌥⌫"]
    let labels = keys.map {
        NSAttributedString(string: $0, attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.78, green: 0.85, blue: 0.97, alpha: 1),
        ])
    }
    let gap: CGFloat = 16
    let widths = labels.map { $0.size().width + 44 }
    var x = canvas.midX - (widths.reduce(0, +) + gap * CGFloat(labels.count - 1)) / 2
    for (label, width) in zip(labels, widths) {
        let pill = CGRect(x: x, y: 82, width: width, height: 62)
        cg.addPath(CGPath(roundedRect: pill, cornerWidth: 16, cornerHeight: 16, transform: nil))
        cg.setFillColor(color(0xFFFFFF, 0.07))
        cg.fillPath()
        cg.addPath(CGPath(roundedRect: pill.insetBy(dx: 1, dy: 1), cornerWidth: 15, cornerHeight: 15, transform: nil))
        cg.setStrokeColor(color(0xFFFFFF, 0.14))
        cg.setLineWidth(2)
        cg.strokePath()
        label.draw(at: NSPoint(
            x: pill.minX + 22, y: pill.minY + (pill.height - label.size().height) / 2))
        x = pill.maxX + gap
    }
}

// MARK: - Main

let fm = FileManager.default
try? fm.createDirectory(atPath: "Assets/AppIcon.iconset", withIntermediateDirectories: true)

// Iconset: render each size directly from vectors (crisper than downscaling)
let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in iconSizes {
    savePNG(makeIcon(px: px), "Assets/AppIcon.iconset/\(name).png")
}

let master = makeIcon(px: 1024)
savePNG(master, "Assets/icon-1024.png")

// Icon Composer layers for the macOS 26+ .icon document
try? fm.createDirectory(atPath: "Assets/AppIcon.icon/Assets", withIntermediateDirectories: true)
savePNG(makeIconLayer(drawFlatBackPane), "Assets/AppIcon.icon/Assets/back.png")
savePNG(makeIconLayer(drawFlatFrontPane), "Assets/AppIcon.icon/Assets/front.png")

let bannerIcon = makeIcon(px: 728).cgImage!
let banner = makeBitmap(1800, 600)
withContext(banner) { drawBanner($0, icon: bannerIcon) }
savePNG(banner, "Assets/banner.png")

// GitHub social preview: exactly 1280x640, GitHub's recommended size.
let og = makeBitmap(1280, 640)
withContext(og) { cg in
    drawSocialPreview(cg, icon: bannerIcon)
}
savePNG(og, "Assets/og-image.png")
