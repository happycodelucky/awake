#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1 else {
    fputs("Usage: generate_app_icon.swift <output_png_path>\n", stderr)
    exit(1)
}

let outputPath = String(arguments[arguments.startIndex])
let outputURL = URL(fileURLWithPath: outputPath)
let canvasSize = CGSize(width: 1024, height: 1024)

func tintedSymbol(name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else {
        return nil
    }

    let tintedImage = NSImage(size: baseImage.size)
    tintedImage.lockFocus()
    let drawRect = NSRect(origin: .zero, size: baseImage.size)
    baseImage.draw(in: drawRect)
    color.set()
    drawRect.fill(using: .sourceAtop)
    tintedImage.unlockFocus()
    return tintedImage
}

func renderMasterImage() -> NSImage {
    let image = NSImage(size: canvasSize)

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        fputs("Failed to create graphics context.\n", stderr)
        exit(1)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setFillColor(NSColor.clear.cgColor)
    context.fill(CGRect(origin: .zero, size: canvasSize))

    let iconRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 204, yRadius: 204)

    context.saveGState()
    iconPath.addClip()

    let backgroundColors = [
        NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.27, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.08, green: 0.32, blue: 0.49, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.58, blue: 0.77, alpha: 1).cgColor
    ]
    let backgroundGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: backgroundColors as CFArray,
        locations: [0, 0.48, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: iconRect.minX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.maxX, y: iconRect.minY),
        options: []
    )

    let glowColors = [
        NSColor(calibratedRed: 0.32, green: 0.99, blue: 0.82, alpha: 0.28).cgColor,
        NSColor(calibratedRed: 0.32, green: 0.99, blue: 0.82, alpha: 0.02).cgColor
    ]
    let glowGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: glowColors as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: 724, y: 724),
        startRadius: 24,
        endCenter: CGPoint(x: 724, y: 724),
        endRadius: 360,
        options: []
    )

    let shineRect = CGRect(x: 120, y: 614, width: 784, height: 244)
    let shinePath = NSBezierPath(roundedRect: shineRect, xRadius: 120, yRadius: 120)
    context.saveGState()
    shinePath.addClip()
    let shineColors = [
        NSColor.white.withAlphaComponent(0.28).cgColor,
        NSColor.white.withAlphaComponent(0.02).cgColor
    ]
    let shineGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: shineColors as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        shineGradient,
        start: CGPoint(x: shineRect.midX, y: shineRect.maxY),
        end: CGPoint(x: shineRect.midX, y: shineRect.minY),
        options: []
    )
    context.restoreGState()

    let trackRect = CGRect(x: 168, y: 248, width: 688, height: 420)
    let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackRect.height / 2, yRadius: trackRect.height / 2)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    context.setLineWidth(54)
    context.addPath(trackPath.cgPath)
    context.strokePath()

    let activeTrackPath = CGMutablePath()
    let radius = trackRect.height / 2
    activeTrackPath.move(to: CGPoint(x: trackRect.minX + 150, y: trackRect.maxY))
    activeTrackPath.addLine(to: CGPoint(x: trackRect.maxX - radius, y: trackRect.maxY))
    activeTrackPath.addArc(
        center: CGPoint(x: trackRect.maxX - radius, y: trackRect.midY),
        radius: radius,
        startAngle: .pi / 2,
        endAngle: 0,
        clockwise: true
    )

    let activeTrackColors = [
        NSColor(calibratedRed: 0.30, green: 0.88, blue: 0.98, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.27, green: 0.92, blue: 0.60, alpha: 1).cgColor
    ]
    let activeTrackGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: activeTrackColors as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.addPath(activeTrackPath)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        activeTrackGradient,
        start: CGPoint(x: trackRect.minX, y: trackRect.maxY),
        end: CGPoint(x: trackRect.maxX, y: trackRect.minY),
        options: []
    )
    context.restoreGState()

    let coreRect = CGRect(x: 256, y: 302, width: 512, height: 298)
    let corePath = NSBezierPath(roundedRect: coreRect, xRadius: 149, yRadius: 149)
    context.saveGState()
    corePath.addClip()
    let coreGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.18, alpha: 0.96).cgColor,
            NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.15, alpha: 0.96).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        coreGradient,
        start: CGPoint(x: coreRect.minX, y: coreRect.maxY),
        end: CGPoint(x: coreRect.maxX, y: coreRect.minY),
        options: []
    )
    context.restoreGState()

    let haloRect = CGRect(x: 310, y: 350, width: 404, height: 204)
    let haloGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.21, green: 0.88, blue: 0.95, alpha: 0.25).cgColor,
            NSColor(calibratedRed: 0.21, green: 0.88, blue: 0.95, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        haloGradient,
        startCenter: CGPoint(x: haloRect.midX, y: haloRect.midY),
        startRadius: 30,
        endCenter: CGPoint(x: haloRect.midX, y: haloRect.midY),
        endRadius: 240,
        options: []
    )

    context.restoreGState()

    let outlinePath = NSBezierPath(roundedRect: iconRect, xRadius: 204, yRadius: 204)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    context.setLineWidth(3)
    context.addPath(outlinePath.cgPath)
    context.strokePath()

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage) -> Data? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    return bitmap.representation(using: .png, properties: [:])
}

func cgImage(from image: NSImage, pixelSize: Int) -> CGImage? {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let representation else { return nil }

    representation.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current = graphicsContext
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    graphicsContext?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return representation.cgImage
}

let masterImage = renderMasterImage()

do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
} catch {
    fputs("Failed to prepare output directory: \(error)\n", stderr)
    exit(1)
}

switch outputURL.pathExtension.lowercased() {
case "png":
    guard let data = pngData(from: masterImage) else {
        fputs("Failed to encode PNG output.\n", stderr)
        exit(1)
    }

    do {
        try data.write(to: outputURL)
    } catch {
        fputs("Failed to write PNG: \(error)\n", stderr)
        exit(1)
    }

case "icns":
    let iconType = UTType(importedAs: "com.apple.icns").identifier as CFString
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, iconType, 0, nil) else {
        fputs("Failed to create ICNS destination.\n", stderr)
        exit(1)
    }

    for pixelSize in [16, 32, 64, 128, 256, 512, 1024] {
        guard let cgImage = cgImage(from: masterImage, pixelSize: pixelSize) else {
            fputs("Failed to render \(pixelSize)x\(pixelSize) icon image.\n", stderr)
            exit(1)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
    }

    guard CGImageDestinationFinalize(destination) else {
        fputs("Failed to finalize ICNS output.\n", stderr)
        exit(1)
    }

default:
    fputs("Unsupported output format. Use .png or .icns\n", stderr)
    exit(1)
}
