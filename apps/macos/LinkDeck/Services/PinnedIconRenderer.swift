import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the generated app icon: the site favicon on a dark squircle, or a
/// deterministic letter tile when no favicon is available.
enum PinnedIconRenderer {
    static func pngData(favicon: Data?, host: String, letter: String) -> Data? {
        let side = 1024
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high

        let bounds = CGRect(x: 36, y: 36, width: 952, height: 952)
        let path = CGPath(roundedRect: bounds, cornerWidth: 210, cornerHeight: 210, transform: nil)

        let hue = Double(StableHash.fnv1a(host) % 360) / 360
        let top = color(hue: hue, saturation: 0.32, brightness: 0.16)
        let bottom = color(hue: hue, saturation: 0.42, brightness: 0.09)

        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [top, bottom] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 120, y: 900),
                end: CGPoint(x: 900, y: 120),
                options: []
            )
        }
        context.restoreGState()

        if let favicon,
           let source = CGImageSourceCreateWithData(favicon as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let maxSide: CGFloat = 520
            let width = CGFloat(image.width)
            let height = CGFloat(image.height)
            guard width > 0, height > 0 else { return nil }
            let scale = min(maxSide / width, maxSide / height)
            let drawWidth = width * scale
            let drawHeight = height * scale
            let rect = CGRect(
                x: (CGFloat(side) - drawWidth) / 2,
                y: (CGFloat(side) - drawHeight) / 2,
                width: drawWidth,
                height: drawHeight
            )
            context.draw(image, in: rect)
        } else {
            drawLetter(letter, hue: hue, in: context, size: CGFloat(side))
        }

        context.addPath(path)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
        context.setLineWidth(3)
        context.strokePath()

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func drawLetter(_ letter: String, hue: Double, in context: CGContext, size: CGFloat) {
        let text = letter.isEmpty ? "L" : String(letter.prefix(1)).uppercased()
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 430, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
        ]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(
            x: size / 2 - bounds.width / 2 - bounds.origin.x,
            y: size / 2 - bounds.height / 2 - bounds.origin.y
        )
        CTLineDraw(line, context)
    }

    private static func color(hue: Double, saturation: Double, brightness: Double) -> CGColor {
        let h = hue * 6
        let sector = floor(h)
        let fraction = h - sector
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (brightness, t, p)
        case 1: rgb = (q, brightness, p)
        case 2: rgb = (p, brightness, t)
        case 3: rgb = (p, q, brightness)
        case 4: rgb = (t, p, brightness)
        default: rgb = (brightness, p, q)
        }
        return CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }
}
