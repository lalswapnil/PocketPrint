// Generates the PocketPrint app icons (light, dark, tinted) as 1024x1024 PNGs.
// Usage: swift scripts/generate_icon.swift <output-directory>
import AppKit
import CoreGraphics

enum Variant { case light, dark, tinted }

let canvas: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func heartPath(center c: CGPoint, size s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + s * 0.38))
    p.addCurve(to: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.08),
               control1: CGPoint(x: c.x - s * 0.12, y: c.y + s * 0.18),
               control2: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.12))
    p.addCurve(to: CGPoint(x: c.x, y: c.y - s * 0.24),
               control1: CGPoint(x: c.x - s * 0.5, y: c.y - s * 0.42),
               control2: CGPoint(x: c.x - s * 0.1, y: c.y - s * 0.42))
    p.addCurve(to: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.08),
               control1: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.42),
               control2: CGPoint(x: c.x + s * 0.5, y: c.y - s * 0.42))
    p.addCurve(to: CGPoint(x: c.x, y: c.y + s * 0.38),
               control1: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.12),
               control2: CGPoint(x: c.x + s * 0.12, y: c.y + s * 0.18))
    p.closeSubpath()
    return p
}

func makeIcon(_ variant: Variant) -> Data {
    let size = Int(canvas)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Work in a top-left origin coordinate system.
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)

    let background: [CGColor]
    let body: CGColor
    let paper: CGColor
    let ink: CGColor
    let accent: CGColor
    let slot: CGColor
    switch variant {
    case .light:
        background = [rgb(0xFF9F66), rgb(0xF2542D), rgb(0xD93A63)]
        body = rgb(0xFFFFFF); paper = rgb(0xFFFDF7); ink = rgb(0x2A2A2E); accent = rgb(0xF2542D); slot = rgb(0x3A3A40)
    case .dark:
        background = [rgb(0x3A3A3F), rgb(0x1E1E21), rgb(0x0E0E10)]
        body = rgb(0xF4F4F6); paper = rgb(0xFFFDF7); ink = rgb(0x2A2A2E); accent = rgb(0xFF7A59); slot = rgb(0x2C2C30)
    case .tinted:
        background = [rgb(0x000000), rgb(0x000000)]
        body = rgb(0xFFFFFF); paper = rgb(0xD9D9D9); ink = rgb(0x000000, 0.85); accent = rgb(0x8C8C8C); slot = rgb(0x5A5A5A)
    }

    let gradient = CGGradient(colorsSpace: colorSpace, colors: background as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: canvas, y: canvas), options: [])

    // Paper strip emerging from the printer, with a torn zig-zag top edge.
    let paperRect = CGRect(x: 332, y: 150, width: 360, height: 420)
    let paperPath = CGMutablePath()
    let teeth = 9
    let toothWidth = paperRect.width / CGFloat(teeth)
    paperPath.move(to: CGPoint(x: paperRect.minX, y: paperRect.maxY))
    paperPath.addLine(to: CGPoint(x: paperRect.minX, y: paperRect.minY + 18))
    for i in 0..<teeth {
        let x0 = paperRect.minX + CGFloat(i) * toothWidth
        paperPath.addLine(to: CGPoint(x: x0 + toothWidth / 2, y: paperRect.minY))
        paperPath.addLine(to: CGPoint(x: x0 + toothWidth, y: paperRect.minY + 18))
    }
    paperPath.addLine(to: CGPoint(x: paperRect.maxX, y: paperRect.maxY))
    paperPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 30, color: rgb(0x000000, 0.25))
    ctx.addPath(paperPath)
    ctx.setFillColor(paper)
    ctx.fillPath()
    ctx.restoreGState()

    // "Printed" content on the strip.
    ctx.addPath(heartPath(center: CGPoint(x: paperRect.midX, y: 290), size: 150))
    ctx.setFillColor(variant == .tinted ? ink : accent)
    ctx.fillPath()
    ctx.setFillColor(ink)
    for (i, width) in [230.0, 180.0, 210.0].enumerated() {
        let y = 390 + CGFloat(i) * 42
        let rect = CGRect(x: paperRect.midX - width / 2, y: y, width: width, height: 18)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil))
        ctx.fillPath()
    }

    // Printer body.
    let bodyRect = CGRect(x: 212, y: 520, width: 600, height: 320)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0x000000, 0.28))
    ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: 110, cornerHeight: 110, transform: nil))
    ctx.setFillColor(body)
    ctx.fillPath()
    ctx.restoreGState()

    // Paper slot.
    let slotRect = CGRect(x: 300, y: 560, width: 424, height: 26)
    ctx.addPath(CGPath(roundedRect: slotRect, cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.setFillColor(slot)
    ctx.fillPath()
    // Paper continuing into the slot.
    ctx.setFillColor(paper)
    ctx.fill(CGRect(x: paperRect.minX, y: paperRect.maxY - 2, width: paperRect.width, height: 8))

    // Power button.
    ctx.addEllipse(in: CGRect(x: 682, y: 720, width: 56, height: 56))
    ctx.setFillColor(accent)
    ctx.fillPath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (variant, name) in [(Variant.light, "AppIcon.png"), (.dark, "AppIcon-Dark.png"), (.tinted, "AppIcon-Tinted.png")] {
    try makeIcon(variant).write(to: outDir.appendingPathComponent(name))
    print("wrote \(name)")
}
