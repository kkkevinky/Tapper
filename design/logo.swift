import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// README logo: a mouse seen from above with the point a finger taps, and a
// monoline "Tapper", drawn from plain geometry (no font). Writes
// Tapper-logo-light.png (black) and Tapper-logo-dark.png (white) at 2x of the
// README display width.
//
// usage: swift design/logo.swift [outDir]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func gray(_ v: CGFloat) -> CGColor { CGColor(colorSpace: srgb, components: [v, v, v, 1])! }

// MARK: Metrics (pixels)

let C: CGFloat = 120                      // cap height (T)
let X: CGFloat = 0.72 * C                 // x-height
let w: CGFloat = 0.12 * X                 // pen width
let D: CGFloat = 0.36 * X                 // descender of p (centerline end)
let o: CGFloat = 0.025 * X                // overshoot of round letters
let r: CGFloat = X / 2 + o - w / 2        // bowl centerline radius
let markHeight: CGFloat = 1.22 * C
let markWidth: CGFloat = 0.62 * markHeight
let markBottom: CGFloat = C / 2 - markHeight / 2
let markGap: CGFloat = 0.40 * C

struct Pen {
    let path = CGMutablePath()
    func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
        path.move(to: CGPoint(x: x0, y: y0)); path.addLine(to: CGPoint(x: x1, y: y1))
    }
    func arc(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, from a0: CGFloat, to a1: CGFloat, clockwise: Bool) {
        path.move(to: CGPoint(x: cx + rad * cos(a0 * .pi / 180), y: cy + rad * sin(a0 * .pi / 180)))
        path.addArc(center: CGPoint(x: cx, y: cy), radius: rad, startAngle: a0 * .pi / 180,
                    endAngle: a1 * .pi / 180, clockwise: clockwise)
    }
}

// MARK: Mark

/// Solid mouse body (`fills`) with the tap point cut out (`cuts`).
func mark(fills: CGMutablePath, cuts: CGMutablePath) {
    let tap = CGPoint(x: markWidth * 0.36, y: markBottom + markHeight * 0.68)
    let dot = 1.15 * w
    let body = CGRect(x: 0, y: markBottom, width: markWidth, height: markHeight)
    fills.addRoundedRect(in: body, cornerWidth: markWidth / 2, cornerHeight: markWidth / 2)
    cuts.addEllipse(in: CGRect(x: tap.x - dot, y: tap.y - dot, width: 2 * dot, height: 2 * dot))
}

// MARK: Glyphs (y up, baseline 0). Each takes its outer left edge and returns its outer right edge.

let tHalf: CGFloat = 0.33 * C - w / 2

func glyphT(_ pen: Pen, _ lx: CGFloat) -> (right: CGFloat, stem: CGFloat) {
    let cx = lx + w / 2 + tHalf
    pen.line(cx - tHalf, C - w / 2, cx + tHalf, C - w / 2)
    pen.line(cx, C - w / 2, cx, w / 2)
    return (cx + tHalf + w / 2, cx)
}

func glyphA(_ pen: Pen, _ lx: CGFloat) -> CGFloat {
    let cx = lx + w / 2 + r
    pen.arc(cx, X / 2, r, from: 0, to: 360, clockwise: false)
    pen.line(cx + r, X - w / 2 + o, cx + r, w / 2)
    return cx + r + w / 2
}

func glyphP(_ pen: Pen, _ lx: CGFloat) -> CGFloat {
    let stem = lx + w / 2
    pen.line(stem, X - w / 2 + o, stem, -D)
    let cx = stem + r
    pen.arc(cx, X / 2, r, from: 0, to: 360, clockwise: false)
    return cx + r + w / 2
}

func glyphE(_ pen: Pen, _ lx: CGFloat) -> CGFloat {
    let cx = lx + w / 2 + r
    pen.line(cx - r, X / 2, cx + r, X / 2)
    pen.arc(cx, X / 2, r, from: 0, to: 325, clockwise: false)
    return cx + r + w / 2
}

func glyphR(_ pen: Pen, _ lx: CGFloat) -> CGFloat {
    let stem = lx + w / 2
    pen.line(stem, X - w / 2 + o, stem, w / 2)
    let rr = r * 0.92
    let cx = stem + rr
    let cy = X + o - w / 2 - rr
    pen.arc(cx, cy, rr, from: 180, to: 52, clockwise: true)
    return cx + rr * cos(52 * .pi / 180) + w / 2
}

func wordmark(_ pen: Pen, at x0: CGFloat) -> CGFloat {
    let t = glyphT(pen, x0)
    var x = glyphA(pen, t.stem + w / 2 + 0.16 * X)   // tucks under the T's arm
    x = glyphP(pen, x + 0.30 * X)                    // stem after stem
    x = glyphP(pen, x + 0.20 * X)                    // stem after bowl
    x = glyphE(pen, x + 0.13 * X)                    // bowl after bowl
    return glyphR(pen, x + 0.20 * X)                 // stem after open e
}

// MARK: Output

let right = wordmark(Pen(), at: markWidth + markGap)
let margin: CGFloat = 6
let bottom = min(-D - w / 2, markBottom) - margin
let top = max(C, markBottom + markHeight) + margin
let width = ceil(margin + right + margin)
let height = ceil(top - bottom)

func render(_ ink: CGColor) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.translateBy(x: margin, y: -bottom)
    let pen = Pen(), fills = CGMutablePath(), cuts = CGMutablePath()
    mark(fills: fills, cuts: cuts)
    _ = wordmark(pen, at: markWidth + markGap)
    ctx.addPath(pen.path)
    ctx.setStrokeColor(ink); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.addPath(fills); ctx.setFillColor(ink); ctx.fillPath()
    ctx.setBlendMode(.clear)
    ctx.addPath(cuts); ctx.fillPath()
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}

write(render(gray(0)), "Tapper-logo-light.png")
write(render(gray(1)), "Tapper-logo-dark.png")
