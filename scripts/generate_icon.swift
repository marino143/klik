#!/usr/bin/env swift
import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

let size: CGFloat = 1024
let bounds = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: bounds.size, flipped: false) { rect in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // Squircle (rounded-rect) background with diagonal gradient
    let radius: CGFloat = 220
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    let topColor = NSColor(red: 0.42, green: 0.36, blue: 0.95, alpha: 1.0)   // indigo
    let bottomColor = NSColor(red: 0.20, green: 0.16, blue: 0.78, alpha: 1.0) // deep indigo
    if let gradient = NSGradient(colors: [topColor, bottomColor]) {
        gradient.draw(in: rect, angle: 270)
    }

    // Subtle highlight at top
    if let highlight = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.18),
        NSColor(white: 1, alpha: 0.0)
    ]) {
        highlight.draw(in: NSRect(x: 0, y: rect.height * 0.55, width: rect.width, height: rect.height * 0.45), angle: 270)
    }

    // Viewfinder frame
    let inset: CGFloat = 220
    let cornerLen: CGFloat = 200
    let lineWidth: CGFloat = 60

    NSColor.white.setStroke()
    let frame = NSBezierPath()
    frame.lineWidth = lineWidth
    frame.lineCapStyle = .round
    frame.lineJoinStyle = .round

    // Top-left
    frame.move(to: NSPoint(x: inset, y: size - inset - cornerLen))
    frame.line(to: NSPoint(x: inset, y: size - inset))
    frame.line(to: NSPoint(x: inset + cornerLen, y: size - inset))
    // Top-right
    frame.move(to: NSPoint(x: size - inset - cornerLen, y: size - inset))
    frame.line(to: NSPoint(x: size - inset, y: size - inset))
    frame.line(to: NSPoint(x: size - inset, y: size - inset - cornerLen))
    // Bottom-right
    frame.move(to: NSPoint(x: size - inset, y: inset + cornerLen))
    frame.line(to: NSPoint(x: size - inset, y: inset))
    frame.line(to: NSPoint(x: size - inset - cornerLen, y: inset))
    // Bottom-left
    frame.move(to: NSPoint(x: inset + cornerLen, y: inset))
    frame.line(to: NSPoint(x: inset, y: inset))
    frame.line(to: NSPoint(x: inset, y: inset + cornerLen))

    frame.stroke()

    // Center: small dot indicating capture
    let dotSize: CGFloat = 110
    let dotRect = NSRect(
        x: (size - dotSize) / 2,
        y: (size - dotSize) / 2,
        width: dotSize, height: dotSize
    )
    NSColor.white.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    // Small inner gap so the dot looks like a "shutter"
    let innerSize: CGFloat = 38
    let innerRect = NSRect(
        x: (size - innerSize) / 2,
        y: (size - innerSize) / 2,
        width: innerSize, height: innerSize
    )
    NSColor(red: 0.31, green: 0.26, blue: 0.86, alpha: 1.0).setFill()
    NSBezierPath(ovalIn: innerRect).fill()

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
do {
    try png.write(to: url)
    print("✅ Wrote \(outputPath) (\(png.count) bytes)")
} catch {
    FileHandle.standardError.write("Failed to write \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
