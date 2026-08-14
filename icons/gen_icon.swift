// Renders System-Bar's app icon — 方案A：精修温度计
// 深色圆角方块 + 精致蓝水银温度计 + 玻璃高光 + 右侧刻度线。1024px master。
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

// ---- 深色圆角底（径向渐变，更立体） ----
let bg = CGRect(x: 0, y: 0, width: size, height: size)
ctx.addPath(CGPath(roundedRect: bg, cornerWidth: 210, cornerHeight: 210, transform: nil))
ctx.clip()
let bgGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.28, 0.34, 0.48),
    color(0.11, 0.14, 0.20),
    color(0.03, 0.04, 0.08),
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawRadialGradient(bgGrad,
                       startCenter: CGPoint(x: size*0.3, y: size*0.75), startRadius: 0,
                       endCenter: CGPoint(x: size*0.5, y: size*0.5), endRadius: size*0.95,
                       options: [])

// 顶部柔和高光条
ctx.setFillColor(color(1, 1, 1, 0.08))
ctx.fill(CGRect(x: 0, y: size*0.90, width: size, height: size*0.10))

let cx = size/2
let bulbCenter = CGPoint(x: cx, y: 760)
let bulbR: CGFloat = 88
let tubeRect = CGRect(x: cx-100, y: 290, width: 200, height: 580)
let tubePath = CGPath(roundedRect: tubeRect, cornerWidth: 100, cornerHeight: 100, transform: nil)

// ---- 玻璃管 ----
ctx.addPath(tubePath); ctx.clip()
let tubeGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.99, 0.99, 1.0),
    color(0.82, 0.87, 0.93),
    color(0.60, 0.68, 0.78),
] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(tubeGrad, start: CGPoint(x: cx, y: 290), end: CGPoint(x: cx, y: 870), options: [])
ctx.resetClip()
ctx.setStrokeColor(color(0.42, 0.5, 0.6, 0.9)); ctx.setLineWidth(12)
ctx.addPath(tubePath); ctx.strokePath()

// ---- 水银柱（蓝-青渐变，内缩保证在管内） ----
let inner = tubeRect.insetBy(dx: 22, dy: 0)
let mercuryTop: CGFloat = 620
let mercuryRect = CGRect(x: inner.minX, y: mercuryTop, width: inner.width, height: inner.maxY - mercuryTop)
ctx.addPath(CGPath(roundedRect: mercuryRect, cornerWidth: inner.width/2, cornerHeight: inner.width/2, transform: nil)); ctx.clip()
let merGrad = CGGradient(colorsSpace: cs, colors: [
    color(0.62, 0.9, 1.0),
    color(0.30, 0.62, 1.0),
    color(0.05, 0.25, 0.82),
] as CFArray, locations: [0, 0.4, 1])!
ctx.drawLinearGradient(merGrad, start: CGPoint(x: cx, y: mercuryTop), end: CGPoint(x: cx, y: 870), options: [])
ctx.resetClip()

// ---- 刻度线（右侧，灰白，标 4 格） ----
ctx.setStrokeColor(color(0.98, 1, 1, 0.55)); ctx.setLineWidth(8)
for i in 0..<4 {
    let y = mercuryTop + CGFloat(i) * 55
    ctx.move(to: CGPoint(x: tubeRect.maxX + 16, y: y))
    ctx.addLine(to: CGPoint(x: tubeRect.maxX + (i == 0 ? 50 : 34), y: y))
}
ctx.strokePath()

// ---- 玻璃高光条 ----
ctx.setStrokeColor(color(1, 1, 1, 0.30)); ctx.setLineWidth(16)
ctx.move(to: CGPoint(x: cx-46, y: mercuryTop+40)); ctx.addLine(to: CGPoint(x: cx-46, y: 850)); ctx.strokePath()
ctx.setStrokeColor(color(1, 1, 1, 0.14)); ctx.setLineWidth(26)
ctx.move(to: CGPoint(x: cx-30, y: mercuryTop+30)); ctx.addLine(to: CGPoint(x: cx-30, y: 840)); ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("icon A written: \(CommandLine.arguments[1])")
