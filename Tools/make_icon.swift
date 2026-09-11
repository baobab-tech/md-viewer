import AppKit
import CoreGraphics
import CoreText
import ImageIO
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Failed to create CGContext")
    }

    // Squircle-ish rounded-rect background.
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = (s - 2 * inset) * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Diagonal blue gradient fill.
    let bgGradient = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.38, green: 0.66, blue: 0.99, alpha: 1),
        CGColor(srgbRed: 0.12, green: 0.32, blue: 0.78, alpha: 1),
    ] as CFArray, locations: [0, 1])!

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: s, y: 0),
        options: []
    )

    // Subtle top-edge highlight.
    let highlight = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: s * 0.55),
        options: []
    )
    ctx.restoreGState()

    // "md" text, centered, white, drawn with Core Text directly into the CGContext.
    let fontSize = s * 0.52
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrString = NSAttributedString(string: "md", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .kern: -s * 0.012,
    ])
    let line = CTLineCreateWithAttributedString(attrString)
    let bounds = CTLineGetImageBounds(line, ctx)
    let textX = (s - bounds.width) / 2 - bounds.minX
    let textY = (s - bounds.height) / 2 - bounds.minY
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, ctx)

    guard let image = ctx.makeImage() else {
        fatalError("Failed to render CGImage")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    let pngUTI = "public.png" as CFString
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, pngUTI, 1, nil) else {
        fatalError("Failed to create image destination at \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fatalError("Failed to finalize image at \(url.path)")
    }
}

for (size, name) in sizes {
    let image = drawIcon(size: size)
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    writePNG(image, to: url)
    FileHandle.standardError.write("wrote \(name) (\(size)px)\n".data(using: .utf8)!)
}
