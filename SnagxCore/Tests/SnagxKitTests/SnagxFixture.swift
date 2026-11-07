import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

/// Builds synthetic `.snagx` archives so tests never depend on real (potentially sensitive) captures.
struct SnagxFixture {
    var canvas = CGSize(width: 40, height: 20)
    var dpi = 144
    var annotations = 0
    var includeFlattened = true
    var includeRaw = true
    var flattenedColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    var rawColor = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    var metadata: [String: Any] = [
        "AppName": "Terminal",
        "AppVersion": "2.14",
        "WindowName": "zsh",
        "CaptureDate": "2026-11-07 17:42:11",
        "OcrText": "hello world",
        "Tags": ["one", "two"],
    ]

    static let pageName = "{00000000-0000-0000-0000-000000000001}"

    var pixelSize: (width: Int, height: Int) {
        (Int(canvas.width) * dpi / 72, Int(canvas.height) * dpi / 72)
    }

    func write(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ name: String, _ data: Data) throws {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

        try add("index.json", json(["Pages": ["\(Self.pageName).json"], "Version": "1.0"]))
        var page: [String: Any] = [
            "CaptureCanvasWidth": Int(canvas.width),
            "CaptureCanvasHeight": Int(canvas.height),
            "DPI": dpi,
            "CaptureObjects": Array(repeating: ["ObjectID": "x"], count: annotations),
            "Effects": [],
            "SoftwareVersion": "2026.4.3",
        ]
        if includeRaw { page["CaptureBackgroundImage"] = "\(Self.pageName).png" }
        try add("\(Self.pageName).json", json(page))
        try add("metadata.json", json(metadata))
        let size = pixelSize
        if includeRaw { try add("\(Self.pageName).png", Self.png(width: size.width, height: size.height, color: rawColor)) }
        if includeFlattened { try add("thumbnail.png", Self.png(width: size.width, height: size.height, color: flattenedColor)) }
    }

    static func image(width: Int, height: Int, color: CGColor) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func png(width: Int, height: Int, color: CGColor) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: width, height: height, color: color), nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnagxKitTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// RGBA of the center pixel, normalized to sRGB 8-bit.
func centerPixel(_ image: CGImage) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return pixel
}

func decode(_ data: Data) -> CGImage {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    return CGImageSourceCreateImageAtIndex(source, 0, nil)!
}
