// Renders MenuTemp's app icon (thermometer on dark rounded square) at 1024px.
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// ---- background: dark rounded square with vertical gradient ----
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 190, cornerHeight: 190, transform: nil))
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.21, 0.26, 0.36),   // top
    color(0.10, 0.12, 0.17),
    color(0.03, 0.04, 0.06),   // bottom
] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// subtle top sheen
ctx.setFillColor(color(1, 1, 1, 0.06))
ctx.fill(CGRect(x: 0, y: size * 0.88, width: size, height: size * 0.12))

let cx = size / 2
let bulbCenter = CGPoint(x: cx, y: 770)
let bulbR: CGFloat = 85
let tubeRect = CGRect(x: cx - 104, y: 300, width: 208, height: 560)
let mercuryInset: CGFloat = 20

// ---- glass tube (capsule, silver gradient) ----
let tubePath = CGPath(roundedRect: tubeRect, cornerWidth: 104, cornerHeight: 104, transform: nil)
ctx.addPath(tubePath)
ctx.clip()
let tubeGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.97, 0.98, 1.0),
    color(0.78, 0.84, 0.90),
    color(0.52, 0.60, 0.70),
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(tubeGrad, start: CGPoint(x: cx, y: 300), end: CGPoint(x: cx, y: 860), options: [])
ctx.resetClip()

// tube outline
ctx.setStrokeColor(color(0.35, 0.42, 0.52, 0.9))
ctx.setLineWidth(10)
ctx.addPath(tubePath)
ctx.strokePath()

// ---- mercury: bulb + column (blue, fully inside the glass tube) ----
let bulbRect = CGRect(x: bulbCenter.x - bulbR, y: bulbCenter.y - bulbR,
                      width: bulbR * 2, height: bulbR * 2)
let merGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.56, 0.82, 1.0),
    color(0.24, 0.55, 1.0),
    color(0.08, 0.28, 0.78),
] as CFArray, locations: [0, 0.55, 1])!

func mercuryCapsule(_ rect: CGRect, corner: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(merGrad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    ctx.restoreGState()
}

mercuryCapsule(bulbRect.insetBy(dx: mercuryInset, dy: mercuryInset), corner: 0)
let column = CGRect(x: tubeRect.minX + mercuryInset, y: 470,
                    width: tubeRect.width - mercuryInset * 2, height: bulbCenter.y - 470)
mercuryCapsule(column, corner: (tubeRect.width - mercuryInset * 2) / 2)

// ---- glass highlight on bulb ----
ctx.saveGState()
ctx.addEllipse(in: bulbRect.insetBy(dx: mercuryInset + 22, dy: mercuryInset + 22))
ctx.clip()
ctx.setFillColor(color(1, 1, 1, 0.35))
ctx.fillEllipse(in: CGRect(x: bulbCenter.x - bulbR + 12, y: bulbCenter.y + 8,
                           width: bulbR * 1.1, height: bulbR * 1.1))
ctx.restoreGState()

// ---- scale ticks on the right ----
ctx.setStrokeColor(color(1, 1, 1, 0.5))
ctx.setLineWidth(6)
ctx.setLineCap(.round)
for i in 0..<7 {
    let y = 330 + CGFloat(i) * 82
    let major = i % 2 == 0
    let x0 = tubeRect.maxX + 34
    ctx.move(to: CGPoint(x: x0, y: y))
    ctx.addLine(to: CGPoint(x: x0 + (major ? 46 : 26), y: y))
    ctx.strokePath()
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("icon written: \(CommandLine.arguments[1])")
