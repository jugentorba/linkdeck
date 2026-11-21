#!/usr/bin/env swift
// Generates every LinkDeck icon from one CoreGraphics drawing.
// Usage: swift tools/make-icons.swift

import AppKit
import CoreGraphics
import Foundation

let ROOT = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let SHARED = ROOT.appendingPathComponent("shared/icon")

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let indigo = rgb(0x5B5BF7)
let violet = rgb(0x8B5CF6)
let deepViolet = rgb(0x6D28D9)

func context(_ pixels: Int) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

/// Three fanned cards with a shield on the front one, in 1024 design units.
func drawGlyph(_ ctx: CGContext) {
    let cardW: CGFloat = 356
    let cardH: CGFloat = 438
    let radius: CGFloat = 66

    func card(center: CGPoint, rotation: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: rotation)
        let rect = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(rgb(0xFFFFFF, alpha))
        ctx.fillPath()
        ctx.restoreGState()
    }

    card(center: CGPoint(x: 430, y: 470), rotation: -0.30, alpha: 0.26)
    card(center: CGPoint(x: 482, y: 500), rotation: -0.16, alpha: 0.52)
    card(center: CGPoint(x: 540, y: 526), rotation: -0.03, alpha: 1.0)

    // Shield on the front card.
    let sw: CGFloat = 132
    let sh: CGFloat = 152
    let origin = CGPoint(x: 566 - sw / 2, y: 380 - sh / 2)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * sw, y: origin.y + y * sh)
    }
    let shield = CGMutablePath()
    shield.move(to: p(0.5, 1.0))
    shield.addCurve(to: p(0.97, 0.14), control1: p(0.80, 0.88), control2: p(0.97, 0.62))
    shield.addLine(to: p(0.97, 0.10))
    shield.addQuadCurve(to: p(0.82, 0.02), control: p(0.97, 0.02))
    shield.addLine(to: p(0.18, 0.02))
    shield.addQuadCurve(to: p(0.03, 0.10), control: p(0.03, 0.02))
    shield.addLine(to: p(0.03, 0.14))
    shield.addCurve(to: p(0.5, 1.0), control1: p(0.03, 0.62), control2: p(0.20, 0.88))
    shield.closeSubpath()
    ctx.addPath(shield)
    ctx.setFillColor(deepViolet)
    ctx.fillPath()

    let check = CGMutablePath()
    check.move(to: p(0.27, 0.46))
    check.addLine(to: p(0.44, 0.30))
    check.addLine(to: p(0.73, 0.64))
    ctx.addPath(check)
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(sw * 0.115)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func drawBackground(_ ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [indigo, violet] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    // Soft highlight in the upper-left.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [rgb(0xFFFFFF, 0.20), rgb(0xFFFFFF, 0.0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: size * 0.24, y: size * 0.82), startRadius: 0,
        endCenter: CGPoint(x: size * 0.24, y: size * 0.82), endRadius: size * 0.62,
        options: []
    )
    ctx.restoreGState()
}

enum Style {
    case square       // full bleed, iOS / PWA / Android legacy
    case rounded      // macOS, padded + rounded + shadow
    case foreground   // transparent glyph for Android adaptive icons
}

func render(_ pixels: Int, style: Style) -> CGImage {
    let ctx = context(pixels)
    let s = CGFloat(pixels) / 1024.0

    switch style {
    case .square:
        drawBackground(ctx, size: CGFloat(pixels))
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: 0, y: 44)
        drawGlyph(ctx)
        ctx.restoreGState()

    case .rounded:
        ctx.saveGState()
        let inset: CGFloat = 64 * s
        let rect = CGRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        let radius: CGFloat = 228 * s
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 26 * s, color: rgb(0x000000, 0.35))
        ctx.addPath(path)
        ctx.setFillColor(violet)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [indigo, violet] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        ctx.restoreGState()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: CGFloat(pixels) * 0.5, y: CGFloat(pixels) * 0.5)
        ctx.scaleBy(x: 0.80 * s, y: 0.80 * s)
        ctx.translateBy(x: -512, y: -512 - 30)
        drawGlyph(ctx)
        ctx.restoreGState()

    case .foreground:
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
        ctx.scaleBy(x: 0.62 * s, y: 0.62 * s)
        ctx.translateBy(x: -512, y: -512 - 30)
        drawGlyph(ctx)
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
    print("wrote \(url.path)")
}

// --- shared icon set ---------------------------------------------------------
writePNG(render(1024, style: .square), to: SHARED.appendingPathComponent("icon-1024.png"))
writePNG(render(512, style: .square), to: SHARED.appendingPathComponent("icon-512.png"))
writePNG(render(192, style: .square), to: SHARED.appendingPathComponent("icon-192.png"))
writePNG(render(180, style: .square), to: SHARED.appendingPathComponent("icon-180.png"))
writePNG(render(64, style: .square), to: SHARED.appendingPathComponent("icon-64.png"))
writePNG(render(48, style: .square), to: SHARED.appendingPathComponent("icon-48.png"))
writePNG(render(1024, style: .square), to: SHARED.appendingPathComponent("ios-AppIcon-1024.png"))

// --- macOS .icns -------------------------------------------------------------
let iconset = SHARED.appendingPathComponent("LinkDeck.iconset")
try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let macSizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in macSizes {
    writePNG(render(px, style: .rounded), to: iconset.appendingPathComponent(name))
}
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", SHARED.appendingPathComponent("AppIcon.icns").path]
try! proc.run()
proc.waitUntilExit()
print("wrote \(SHARED.appendingPathComponent("AppIcon.icns").path)")

// --- Android -----------------------------------------------------------------
let androidSizes: [(String, Int)] = [
    ("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192),
]
for (bucket, px) in androidSizes {
    let dir = SHARED.appendingPathComponent("android/mipmap-\(bucket)")
    writePNG(render(px, style: .square), to: dir.appendingPathComponent("ic_launcher.png"))
    let fgScale = px * 108 / 48
    writePNG(render(fgScale, style: .foreground), to: dir.appendingPathComponent("ic_launcher_foreground.png"))
}

// Round legacy icon (circle crop).
func roundIcon(_ pixels: Int) -> CGImage {
    let ctx = context(pixels)
    let s = CGFloat(pixels) / 1024.0
    ctx.addEllipse(in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
    ctx.clip()
    drawBackground(ctx, size: CGFloat(pixels))
    ctx.saveGState()
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 44)
    drawGlyph(ctx)
    ctx.restoreGState()
    return ctx.makeImage()!
}
for (bucket, px) in androidSizes {
    writePNG(roundIcon(px), to: SHARED.appendingPathComponent("android/mipmap-\(bucket)/ic_launcher_round.png"))
}

// --- PWA ---------------------------------------------------------------------
let pwa = ROOT.appendingPathComponent("apps/pwa/icons")
writePNG(render(1024, style: .square), to: pwa.appendingPathComponent("icon-1024.png"))
writePNG(render(512, style: .square), to: pwa.appendingPathComponent("icon-512.png"))
writePNG(render(192, style: .square), to: pwa.appendingPathComponent("icon-192.png"))
writePNG(render(180, style: .square), to: pwa.appendingPathComponent("apple-touch-icon.png"))
writePNG(render(64, style: .square), to: pwa.appendingPathComponent("favicon.png"))
