import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// App icon: the logo's mark in white on a black macOS icon body. Every size is
// drawn from the geometry at its own resolution; 16 and 32 px get a larger mark
// and tap point so they stay readable.
//
// usage: swift design/icon.swift [iconsetDir]

let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: srgb, components: [v, v, v, a])! }

func superellipse(_ rect: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...720 {
        let t = CGFloat(i) * .pi / 360
        let ct = cos(t), st = sin(t)
        let pt = CGPoint(x: rect.midX + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n),
                         y: rect.midY + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

func icon(size: Int) -> CGImage {
    let s = CGFloat(size), k = s / 1024
    let small = size <= 32
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)

    // Body on Apple's macOS grid: 824 x 824 centered, with a soft drop shadow.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = superellipse(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: max(20 * k, 1), color: gray(0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(gray(0)); ctx.fillPath()
    ctx.restoreGState()

    // Mark: capsule plus the tap point, same proportions as the logo.
    let markHeight = 824 * k * (small ? 0.64 : 0.54)
    let markWidth = 0.62 * markHeight
    let mark = CGRect(x: body.midX - markWidth / 2, y: body.midY - markHeight / 2, width: markWidth, height: markHeight)
    ctx.addPath(CGPath(roundedRect: mark, cornerWidth: markWidth / 2, cornerHeight: markWidth / 2, transform: nil))
    ctx.setFillColor(gray(1)); ctx.fillPath()

    let dot = markWidth * (small ? 0.19 : 0.135)
    let tap = CGPoint(x: mark.minX + markWidth * 0.36, y: mark.minY + markHeight * 0.68)
    ctx.addEllipse(in: CGRect(x: tap.x - dot, y: tap.y - dot, width: 2 * dot, height: 2 * dot))
    ctx.setFillColor(gray(0)); ctx.fillPath()
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
var rendered: [Int: CGImage] = [:]
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let image = rendered[px] ?? icon(size: px)
        rendered[px] = image
        write(image, "\(iconsetDir)/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png")
    }
}
