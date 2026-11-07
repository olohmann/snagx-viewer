import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    /// Snagit capture, declared by Snagit and imported by Snagx Viewer.
    public static let snagx = UTType(importedAs: "com.techsmith.snagx", conformingTo: .image)
}

public enum ExportFormat: Sendable, Hashable {
    case png
    /// `quality` in 0...1.
    case jpeg(quality: Double)

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

public enum ExportScale: String, Sendable, Hashable, CaseIterable, Identifiable {
    /// Full captured resolution (2x on Retina).
    case native
    /// One pixel per point.
    case oneX

    public var id: String { rawValue }
}

public struct ExportOptions: Sendable, Hashable {
    public var format: ExportFormat
    public var scale: ExportScale
    public var variant: ImageVariant

    public init(format: ExportFormat = .png, scale: ExportScale = .native, variant: ImageVariant = .flattened) {
        self.format = format
        self.scale = scale
        self.variant = variant
    }

    /// File name suffix distinguishing non-default variants, e.g. `-raw@1x`.
    public var fileNameSuffix: String {
        (variant == .raw ? "-raw" : "") + (scale == .oneX ? "@1x" : "")
    }
}

public enum SnagxExporter {
    /// Renders the image for `options` (variant + scale).
    public static func image(from document: SnagxDocument, options: ExportOptions) throws -> CGImage {
        let image = try document.image(options.variant)
        guard options.scale == .oneX else { return image }
        let scale = document.pixelScale(of: image)
        guard scale > 1.001 else { return image }
        let size = CGSize(width: max(1, (CGFloat(image.width) / scale).rounded()),
                          height: max(1, (CGFloat(image.height) / scale).rounded()))
        return try resized(image, to: size)
    }

    /// Encodes `image` as PNG or JPEG. JPEG has no alpha, so transparency is composited on white.
    public static func encode(_ image: CGImage, format: ExportFormat, pixelScale: CGFloat = 1) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else {
            throw SnagxError.encodeFailed
        }
        let dpi = 72 * max(pixelScale, 1)
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        var output = image
        if case .jpeg(let quality) = format {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1)
            output = try flattenedOnWhite(image)
        }
        CGImageDestinationAddImage(destination, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SnagxError.encodeFailed }
        return data as Data
    }

    /// Exports to `url` (overwriting). Returns the render-status warning, if any.
    @discardableResult
    public static func export(_ document: SnagxDocument, options: ExportOptions, to url: URL) throws -> String? {
        let image = try image(from: document, options: options)
        let scale = options.scale == .native ? document.pixelScale(of: image) : 1
        let data = try encode(image, format: options.format, pixelScale: scale)
        try data.write(to: url, options: .atomic)
        return options.variant == .flattened ? document.renderStatus.warning : nil
    }

    /// `<directory>/<source name><suffix>.<ext>`, made unique unless `overwrite` is set.
    public static func outputURL(for source: URL, in directory: URL, options: ExportOptions, overwrite: Bool) -> URL {
        outputURL(for: source, in: directory, options: options) { candidate in
            !overwrite && FileManager.default.fileExists(atPath: candidate.path)
        }
    }

    /// First of `<base>.<ext>`, `<base> 2.<ext>`, … for which `isTaken` returns false.
    static func outputURL(for source: URL, in directory: URL, options: ExportOptions,
                          isTaken: (URL) -> Bool) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + options.fileNameSuffix
        let ext = options.format.fileExtension
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while isTaken(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    // MARK: - Drawing

    static func resized(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let context = try makeContext(width: Int(size.width), height: Int(size.height),
                                      colorSpace: image.colorSpace, alpha: true)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let result = context.makeImage() else { throw SnagxError.encodeFailed }
        return result
    }

    static func flattenedOnWhite(_ image: CGImage) throws -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let context = try makeContext(width: image.width, height: image.height,
                                      colorSpace: image.colorSpace, alpha: false)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let result = context.makeImage() else { throw SnagxError.encodeFailed }
        return result
    }

    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace?, alpha: Bool) throws -> CGContext {
        let bitmapInfo = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        // Keep the capture's color profile when it can back an RGB bitmap context; otherwise use sRGB.
        let candidates = [colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in candidates where space.model == .rgb {
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo) {
                return context
            }
        }
        throw SnagxError.encodeFailed
    }
}
