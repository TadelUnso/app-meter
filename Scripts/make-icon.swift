#!/usr/bin/env swift
// make-icon.swift — generates Resources/AppIcon.icns from CoreGraphics primitives.
// Run from repo root: swift Scripts/make-icon.swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Color helpers

func cgColor(hex: UInt32) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(red: r, green: g, blue: b, alpha: 1.0)
}

// MARK: - Master image (1024 × 1024)

let masterSize = 1024

guard let ctx = CGContext(
    data: nil,
    width: masterSize,
    height: masterSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("ERROR: could not create CGContext\n", stderr)
    exit(1)
}

// Background rounded rect: inset 100 pt, corner radius 180 — Theme.panel.
let bgRect = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.setFillColor(cgColor(hex: 0x1E2230))
ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.fillPath()

// A dial, echoing the menu bar's gauge.with.needle glyph in the widget's own
// colours rather than copying its monochrome strokes. Centred horizontally,
// sitting below the canvas's vertical middle so the arc's opening at the
// bottom has room before it reaches the background rect's edge.
let dialCenter = CGPoint(x: CGFloat(masterSize) / 2, y: 460)
let dialRadius: CGFloat = 320
let arcWidth: CGFloat = 90

// Angles use the standard math convention (0° = east, increasing
// counterclockwise). The gap sits at the bottom: the arc runs from
// lower-left, up over the top, to lower-right — 240° of a 360° circle,
// leaving a 120° opening below.
let arcStart = 210.0 * CGFloat.pi / 180
let arcEnd = -30.0 * CGFloat.pi / 180
// Two thirds of the sweep, from the start — the "reached" portion of the
// scale, and where the needle points.
let accentEnd = arcStart - (arcStart - arcEnd) * (2.0 / 3.0)

ctx.setLineCap(.round)
ctx.setLineWidth(arcWidth)

ctx.setStrokeColor(cgColor(hex: 0x404557)) // Theme.track — the unfilled scale
ctx.beginPath()
ctx.addArc(center: dialCenter, radius: dialRadius, startAngle: arcStart, endAngle: arcEnd, clockwise: true)
ctx.strokePath()

ctx.setStrokeColor(cgColor(hex: 0xA6D189)) // Theme.accent — installs climbing
ctx.beginPath()
ctx.addArc(center: dialCenter, radius: dialRadius, startAngle: arcStart, endAngle: accentEnd, clockwise: true)
ctx.strokePath()

// Needle stops at the arc's inner edge rather than crossing it, so the tip
// doesn't merge into the stroke it's pointing at.
let needleLength = dialRadius - arcWidth / 2
let needleTip = CGPoint(
    x: dialCenter.x + needleLength * cos(accentEnd),
    y: dialCenter.y + needleLength * sin(accentEnd)
)
ctx.setStrokeColor(cgColor(hex: 0xC7CCDE)) // Theme.text
ctx.setLineWidth(28)
ctx.beginPath()
ctx.move(to: dialCenter)
ctx.addLine(to: needleTip)
ctx.strokePath()

// Hub circle over the needle's base so it reads as a needle, not a spoke.
let hubRadius: CGFloat = 48
ctx.setFillColor(cgColor(hex: 0xC7CCDE)) // Theme.text
ctx.addPath(CGPath(
    ellipseIn: CGRect(x: dialCenter.x - hubRadius, y: dialCenter.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2),
    transform: nil
))
ctx.fillPath()

guard let masterImage = ctx.makeImage() else {
    fputs("ERROR: could not create master CGImage\n", stderr)
    exit(1)
}

// MARK: - Iconset sizes

struct IconFile {
    let filename: String
    let pixels: Int
}

let iconFiles: [IconFile] = [
    IconFile(filename: "icon_16x16.png", pixels: 16),
    IconFile(filename: "icon_16x16@2x.png", pixels: 32),
    IconFile(filename: "icon_32x32.png", pixels: 32),
    IconFile(filename: "icon_32x32@2x.png", pixels: 64),
    IconFile(filename: "icon_128x128.png", pixels: 128),
    IconFile(filename: "icon_128x128@2x.png", pixels: 256),
    IconFile(filename: "icon_256x256.png", pixels: 256),
    IconFile(filename: "icon_256x256@2x.png", pixels: 512),
    IconFile(filename: "icon_512x512.png", pixels: 512),
    IconFile(filename: "icon_512x512@2x.png", pixels: 1024),
]

// MARK: - Temp iconset directory

let fm = FileManager.default
let tempDir = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

for icon in iconFiles {
    guard let scaledCtx = CGContext(
        data: nil,
        width: icon.pixels,
        height: icon.pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("ERROR: could not create context for \(icon.filename)\n", stderr)
        exit(1)
    }

    scaledCtx.interpolationQuality = .high
    scaledCtx.draw(masterImage, in: CGRect(x: 0, y: 0, width: icon.pixels, height: icon.pixels))

    guard let scaledImage = scaledCtx.makeImage() else {
        fputs("ERROR: could not create image for \(icon.filename)\n", stderr)
        exit(1)
    }

    let destURL = tempDir.appendingPathComponent(icon.filename)
    let nsImage = NSBitmapImageRep(cgImage: scaledImage)
    guard let pngData = nsImage.representation(using: .png, properties: [:]) else {
        fputs("ERROR: PNG encoding failed for \(icon.filename)\n", stderr)
        exit(1)
    }
    try pngData.write(to: destURL)
}

// MARK: - Run iconutil

let outputPath = "Resources/AppIcon.icns"

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", tempDir.path, "-o", outputPath]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("ERROR: iconutil exited with status \(process.terminationStatus)\n", stderr)
    exit(1)
}

try fm.removeItem(at: tempDir)

print("Icon written to: \(outputPath)")
