import AppKit
import CoreGraphics
import CoreText
import ImageIO
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

// Finder treats image pixels as points, not actual pixels — so the image must
// be exactly window-content-sized in pixels (600x400). It will be slightly soft
// on Retina; a multi-rep TIFF would fix that.
let logicalW: CGFloat = 600
let logicalH: CGFloat = 400
let width  = Int(logicalW)
let height = Int(logicalH)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create context")
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

let w = logicalW
let h = logicalH

// Soft vertical gradient background.
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(srgbRed: 0.97, green: 0.98, blue: 1.00, alpha: 1),
    CGColor(srgbRed: 0.90, green: 0.93, blue: 0.97, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(
    bg,
    start: CGPoint(x: 0, y: h),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Arrow geometry — points from the app on the left to the Applications shortcut on the right.
// Icons are placed by Finder at roughly (150, 180) and (450, 180) measured from window's top-left.
// Our CG y-axis is up; the visual center for icons is around y = h - 180 = 220.
// The arrow sits a bit higher than the icon labels so it looks like it's pointing between the two icons.
let arrowY = h - 200
let arrowStartX: CGFloat = w * 0.40
let arrowEndX:   CGFloat = w * 0.60
let strokeColor = CGColor(srgbRed: 0.36, green: 0.50, blue: 0.70, alpha: 0.85)

ctx.setStrokeColor(strokeColor)
ctx.setFillColor(strokeColor)
ctx.setLineCap(.round)
ctx.setLineWidth(8)
ctx.move(to: CGPoint(x: arrowStartX, y: arrowY))
ctx.addLine(to: CGPoint(x: arrowEndX - 6, y: arrowY))
ctx.strokePath()

// Arrowhead.
let headTip = CGPoint(x: arrowEndX + 14, y: arrowY)
let headLen: CGFloat = 26
let headWidth: CGFloat = 22
ctx.move(to: headTip)
ctx.addLine(to: CGPoint(x: headTip.x - headLen, y: arrowY + headWidth / 2))
ctx.addLine(to: CGPoint(x: headTip.x - headLen, y: arrowY - headWidth / 2))
ctx.closePath()
ctx.fillPath()

// Hint label below the arrow.
let label = NSAttributedString(string: "Drag to Applications", attributes: [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 0.30, green: 0.40, blue: 0.55, alpha: 1.0),
    .kern: 0.3,
])
let labelLine = CTLineCreateWithAttributedString(label)
let bounds = CTLineGetImageBounds(labelLine, ctx)
let labelX = (w - bounds.width) / 2 - bounds.minX
let labelY = arrowY - 36 - bounds.minY
ctx.textPosition = CGPoint(x: labelX, y: labelY)
CTLineDraw(labelLine, ctx)

// Top title.
let title = NSAttributedString(string: "Markdown Viewer", attributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.18, green: 0.25, blue: 0.40, alpha: 1.0),
    .kern: -0.2,
])
let titleLine = CTLineCreateWithAttributedString(title)
let tBounds = CTLineGetImageBounds(titleLine, ctx)
let titleX = (w - tBounds.width) / 2 - tBounds.minX
let titleY = h - 56 - tBounds.minY
ctx.textPosition = CGPoint(x: titleX, y: titleY)
CTLineDraw(titleLine, ctx)

guard let image = ctx.makeImage() else {
    fatalError("Failed to make image")
}
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Failed to create destination")
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
    fatalError("Failed to finalize PNG")
}
FileHandle.standardError.write("wrote \(outPath) (\(width)x\(height))\n".data(using: .utf8)!)
