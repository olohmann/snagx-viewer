// Regenerate the app icon set from the full-bleed artwork:
//   swift Design/compose-icon.swift Design/AppIcon-artwork.png App/SnagxViewer/Assets.xcassets/AppIcon.appiconset

import AppKit
import SwiftUI

let args = CommandLine.arguments
let art = NSImage(contentsOfFile: args[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let outDir = URL(fileURLWithPath: args[2])

// macOS icon grid: 1024 canvas, 824 body inset by 100, continuous corners.
func master() -> CGImage {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(art, in: body)
    // Subtle top highlight edge.
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18)); ctx.setLineWidth(4); ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

func resized(_ image: CGImage, _ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}

let m = master()
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(resized(m, points * scale), name)
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("Contents.json"))
