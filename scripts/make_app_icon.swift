#!/usr/bin/env swift
//
//  make_app_icon.swift
//  Regenerates the three 1024x1024 App Store icon variants from `languageDLCLogo.png`.
//
//  Run from the repo root:
//      swift scripts/make_app_icon.swift
//
//  The source logo is a lockup: the globe/speech-bubble/padlock emblem on top, the
//  "LanguageDLC" wordmark underneath. An app icon is rendered as small as 40pt, where a
//  wordmark is illegible mush, so this crops the emblem out (its bounding box is found by
//  scanning for pixels that differ from the navy ground, restricted to the band above the
//  wordmark) and recomposes it centred on a fresh square canvas.
//
//  Three variants, matching the three slots in AppIcon.appiconset/Contents.json:
//    - Light   the emblem as-is on its own navy
//    - Dark    the same, dimmed
//    - Tinted  the same, flattened to luminance; iOS applies the user's tint itself
//
//  Every variant is composited onto Theme.navy (#021029) — the logo's *own* ground — and only
//  then transformed as a whole. Filling the canvas with a different colour than the cropped
//  region carries would leave the crop visible as a rectangle behind the emblem; transforming
//  ground and mark together is what keeps the edge invisible.
//
//  Icons must be fully opaque with no alpha channel, so every variant is composited onto a
//  filled ground rather than left transparent.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Configuration

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = repoRoot.appendingPathComponent("languageDLCLogo.png")
let outputDir = repoRoot.appendingPathComponent("languageDLC/Assets.xcassets/AppIcon.appiconset")

let canvasSide = 1024
/// Share of the canvas the emblem's longest side occupies. The emblem is a circle with a
/// padlock spur at its top right, so it needs a little more breathing room than a plain
/// square mark would.
let emblemFill = 0.82

/// The source logo's ground — and therefore the canvas ground for every variant.
let navyGround = (r: 2, g: 16, b: 41)   // #021029  Theme.navy

/// How far the dark variant is dimmed relative to the light one. Applied to the whole canvas,
/// so #021029 lands near Theme.navyDeep (#010818) and the emblem dims with it.
let darkDimming = 0.62

/// Rows below this are the wordmark, not the emblem. Derived from the source's row profile:
/// emblem content runs y 143...801, the wordmark y 870...1030, with a clean gap between.
let wordmarkTop = 830

// MARK: - Load

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not read \(sourceURL.path) — run this from the repo root.")
}

let w = logo.width, h = logo.height
let rgb = CGColorSpaceCreateDeviceRGB()
let opaqueBitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

/// The logo redrawn into a buffer we can inspect pixel by pixel.
var pixels = [UInt8](repeating: 0, count: w * h * 4)
pixels.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(logo, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// MARK: - Find the emblem

/// True where a pixel is far enough from the navy ground to be part of the mark. The threshold
/// is deliberately loose: the emblem has soft anti-aliased edges and a drop shadow, and pulling
/// a few shadow pixels into the crop is harmless, while cutting the glow off is visible.
func isMark(_ x: Int, _ y: Int) -> Bool {
    let i = (y * w + x) * 4
    return abs(Int(pixels[i])     - navyGround.r)
         + abs(Int(pixels[i + 1]) - navyGround.g)
         + abs(Int(pixels[i + 2]) - navyGround.b) > 60
}

var minX = w, maxX = 0, minY = h, maxY = 0
for y in 0..<min(wordmarkTop, h) {
    for x in 0..<w where isMark(x, y) {
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard minX < maxX, minY < maxY else { fatalError("Found no emblem pixels — is the logo still navy-backed?") }

/// A few pixels of slack so the crop never clips the emblem's own antialiasing.
let pad = 8
let cropRect = CGRect(x: max(0, minX - pad),
                      y: max(0, minY - pad),
                      width: min(w, maxX + pad) - max(0, minX - pad),
                      height: min(h, maxY + pad) - max(0, minY - pad))
guard let emblem = logo.cropping(to: cropRect) else { fatalError("crop failed") }

print("emblem bbox x \(minX)...\(maxX), y \(minY)...\(maxY) -> crop \(Int(cropRect.width))x\(Int(cropRect.height))")

// MARK: - Compose

/// Where the emblem lands on the square canvas: scaled so its longest side is `emblemFill` of
/// the canvas, then centred on both axes.
var emblemRect: CGRect {
    let side = Double(canvasSide)
    let scale = side * emblemFill / Double(max(cropRect.width, cropRect.height))
    let dw = Double(cropRect.width) * scale
    let dh = Double(cropRect.height) * scale
    return CGRect(x: (side - dw) / 2, y: (side - dh) / 2, width: dw, height: dh)
}

/// The emblem centred on its own navy — the common base all three variants transform.
func composeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: canvasSide, height: canvasSide, bitsPerComponent: 8,
                        bytesPerRow: 0, space: rgb, bitmapInfo: opaqueBitmapInfo)!
    ctx.setFillColor(red: Double(navyGround.r) / 255, green: Double(navyGround.g) / 255,
                     blue: Double(navyGround.b) / 255, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
    ctx.interpolationQuality = .high
    ctx.draw(emblem, in: emblemRect)
    guard let composed = ctx.makeImage() else { fatalError("compose failed") }
    return composed
}

/// Rewrites every pixel of a composed icon through `transform`. Whole-canvas by construction,
/// which is what keeps the crop's edge from reappearing.
func mapPixels(_ image: CGImage,
               _ transform: (Double, Double, Double) -> (Double, Double, Double)) -> CGImage {
    let count = canvasSide * canvasSide * 4
    var data = [UInt8](repeating: 0, count: count)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: canvasSide, height: canvasSide,
                            bitsPerComponent: 8, bytesPerRow: canvasSide * 4, space: rgb,
                            bitmapInfo: opaqueBitmapInfo)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
    }
    for i in stride(from: 0, to: count, by: 4) {
        let (r, g, b) = transform(Double(data[i])     / 255,
                                  Double(data[i + 1]) / 255,
                                  Double(data[i + 2]) / 255)
        data[i]     = UInt8(max(0, min(255, (r * 255).rounded())))
        data[i + 1] = UInt8(max(0, min(255, (g * 255).rounded())))
        data[i + 2] = UInt8(max(0, min(255, (b * 255).rounded())))
    }
    return data.withUnsafeMutableBytes { raw -> CGImage in
        let ctx = CGContext(data: raw.baseAddress, width: canvasSide, height: canvasSide,
                            bitsPerComponent: 8, bytesPerRow: canvasSide * 4, space: rgb,
                            bitmapInfo: opaqueBitmapInfo)!
        return ctx.makeImage()!
    }
}

func write(_ image: CGImage, to name: String) {
    let url = outputDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(name)") }
    print("wrote \(name)")
}

let base = composeBase()

write(base, to: "AppIcon-Light.png")

write(mapPixels(base) { r, g, b in (r * darkDimming, g * darkDimming, b * darkDimming) },
      to: "AppIcon-Dark.png")

// Rec. 709 luminance. iOS reads a tinted icon as a single-channel mask and applies the user's
// chosen tint across it, so what matters is the mark's brightness against its ground, not hue.
write(mapPixels(base) { r, g, b in
    let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return (y, y, y)
}, to: "AppIcon-Tinted.png")
