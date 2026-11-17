// Draws the ScooterRide app icon: an original kick-scooter glyph inside a speed-gauge arc.
// Pure Core Graphics (no SF Symbols, which Apple's license excludes from app icons).
// Usage: swift scripts/make-icon.swift <output.png> [size]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make-icon.swift <output.png> [size]"); exit(2) }
let size = args.count >= 3 ? Int(args[2]) ?? 1024 : 1024
let s = CGFloat(size) / 1024   // all coordinates below are on a 1024 canvas, y up

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Opaque RGB: App Store icons must not have an alpha channel.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
ctx.scaleBy(x: s, y: s)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Background: night navy to teal, top-left to bottom-right.
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x0F2B46), rgb(0x0B6E5F)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

// Soft light behind the glyph.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 480), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 480), endRadius: 420, options: [])

// Speed gauge: a 240° arc open at the bottom, two-thirds "filled".
let center = CGPoint(x: 512, y: 470), radius: CGFloat = 350
func arc(from a0: CGFloat, to a1: CGFloat, color: CGColor, width: CGFloat) {
    ctx.beginPath()
    ctx.addArc(center: center, radius: radius, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: true)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokePath()
}
arc(from: 210, to: -30, color: rgb(0xFFFFFF, 0.16), width: 46)
arc(from: 210, to: 20, color: rgb(0x45E6A6), width: 46)
// Needle tip dot where the fill ends.
let tip = CGPoint(x: center.x + radius * cos(20 * .pi / 180), y: center.y + radius * sin(20 * .pi / 180))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: tip.x - 30, y: tip.y - 30, width: 60, height: 60))

// Scooter glyph (white): two wheels, low deck, raked stem and handlebar.
let white = rgb(0xFFFFFF)
ctx.setStrokeColor(white)
ctx.setFillColor(white)
func line(_ pts: [CGPoint], width: CGFloat) {
    ctx.beginPath(); ctx.addLines(between: pts); ctx.setLineWidth(width); ctx.strokePath()
}
func wheel(_ c: CGPoint) {
    ctx.setLineWidth(34)
    ctx.strokeEllipse(in: CGRect(x: c.x - 78, y: c.y - 78, width: 156, height: 156))
    ctx.fillEllipse(in: CGRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40))
}
let rear = CGPoint(x: 330, y: 330), front = CGPoint(x: 700, y: 330)
wheel(rear)
wheel(front)
// Deck from the rear axle forward, then up into the stem.
ctx.addPath(CGPath(roundedRect: CGRect(x: 392, y: 352, width: 278, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.fillPath()
line([CGPoint(x: 640, y: 374), CGPoint(x: 680, y: 374)], width: 44)
// Stem: front axle up and back to the handlebar.
line([front, CGPoint(x: 643, y: 708)], width: 40)
// Handlebar grip.
line([CGPoint(x: 583, y: 716), CGPoint(x: 686, y: 700)], width: 38)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
