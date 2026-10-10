#!/usr/bin/env swift
import AppKit

// Independently drawn, layered glass artwork. No third-party images.
let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
let cg = NSGraphicsContext.current!.cgContext
cg.setAllowsAntialiasing(true)
cg.setShouldAntialias(true)
func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func path(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func gradient(_ shape: NSBezierPath, _ colors: [NSColor], _ angle: CGFloat) {
    NSGradient(colors: colors)!.draw(in: shape, angle: angle)
}
func shadow(_ blur: CGFloat, _ opacity: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.shadowColor = color(0x020821, opacity)
    shadow.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}
let body = path(NSRect(x: 60, y: 60, width: 904, height: 904), 214)
shadow(24, 0.24) { color(0x14243A).setFill(); body.fill() }
gradient(body, [color(0x344F70), color(0x15243C), color(0x252440)], -65)
color(0xF0F8FF, 0.20).setStroke(); body.lineWidth = 2; body.stroke()

let rearRect = NSRect(x: 199, y: 415, width: 546, height: 360)
let rear = path(rearRect, 70)
shadow(24, 0.30) { gradient(rear, [color(0xCAD4FF, 0.95), color(0x8A8AEF, 0.90), color(0x646ECB, 0.74)], -80) }
color(0xFFFFFF, 0.68).setStroke(); rear.lineWidth = 3; rear.stroke()
NSGraphicsContext.saveGraphicsState()
rear.addClip()
gradient(path(NSRect(x: 209, y: 666, width: 526, height: 104), 60), [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)], -90)
NSGraphicsContext.restoreGraphicsState()

let frontRect = NSRect(x: 285, y: 250, width: 550, height: 378)
let front = path(frontRect, 74)
shadow(36, 0.38) { gradient(front, [color(0xB2F5F9, 0.96), color(0x67CBEA, 0.95), color(0x4288D4, 0.92)], -70) }
color(0xF0FDFF, 0.82).setStroke(); front.lineWidth = 3; front.stroke()
let inner = path(frontRect.insetBy(dx: 8, dy: 8), 67)
color(0xFFFFFF, 0.12).setStroke(); inner.lineWidth = 2; inner.stroke()
NSGraphicsContext.saveGraphicsState()
front.addClip()
gradient(path(NSRect(x: 290, y: 530, width: 540, height: 130), 68), [color(0xFFFFFF, 0.32), color(0xFFFFFF, 0)], -90)
let horizon = NSBezierPath()
horizon.move(to: NSPoint(x: 314, y: 547)); horizon.line(to: NSPoint(x: 807, y: 547))
color(0xFFFFFF, 0.21).setStroke(); horizon.lineWidth = 2; horizon.stroke()
for x in [332.0, 356.0, 380.0] {
    color(0xFFFFFF, 0.72).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: 578, width: 9, height: 9)).fill()
}
NSGraphicsContext.restoreGraphicsState()

// A simple play mark remains recognizable at menu and Finder icon sizes.
let play = NSBezierPath()
play.move(to: NSPoint(x: 518, y: 349))
play.curve(to: NSPoint(x: 531, y: 342), controlPoint1: NSPoint(x: 518, y: 340), controlPoint2: NSPoint(x: 523, y: 338))
play.line(to: NSPoint(x: 623, y: 398))
play.curve(to: NSPoint(x: 623, y: 412), controlPoint1: NSPoint(x: 632, y: 404), controlPoint2: NSPoint(x: 632, y: 407))
play.line(to: NSPoint(x: 531, y: 468))
play.curve(to: NSPoint(x: 518, y: 461), controlPoint1: NSPoint(x: 523, y: 472), controlPoint2: NSPoint(x: 518, y: 468))
play.close()
shadow(10, 0.15) { color(0xFFFFFF, 0.95).setFill(); play.fill() }

NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
print(url.path)
