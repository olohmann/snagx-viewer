import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZIPFoundation

/// A parsed Snagit capture (`.snagx`, a ZIP archive).
///
/// `thumbnail.png` inside the archive is Snagit's full-resolution *flattened* render
/// (annotations, blur redactions and crops applied). The page's background image is the
/// *raw* capture, which may contain content the user redacted.
public final class SnagxDocument: Sendable {
    public enum Contents: Sendable {
        /// Load flattened and raw images.
        case all
        /// Load only what is needed to show the flattened image (Quick Look, thumbnails).
        case flattenedOnly
    }

    static let flattenedEntryName = "thumbnail.png"
    static let maxEntrySize: UInt64 = 1 << 30

    public let metadata: SnagxMetadata
    public let page: SnagxPage
    public let pageCount: Int
    public let renderStatus: RenderStatus
    /// Encoded PNG of Snagit's flattened render, if present.
    public let flattenedImageData: Data?
    /// Encoded raw capture, if loaded.
    public let rawImageData: Data?

    public convenience init(url: URL, contents: Contents = .all) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw SnagxError.notAnArchive
        }
        try self.init(archive: archive, contents: contents)
    }

    public convenience init(data: Data, contents: Contents = .all) throws {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw SnagxError.notAnArchive
        }
        try self.init(archive: archive, contents: contents)
    }

    private init(archive: Archive, contents: Contents) throws {
        let pageNames = try Self.pageNames(in: archive)
        guard let pageName = pageNames.first else { throw SnagxError.missingEntry("index.json") }
        pageCount = pageNames.count
        page = SnagxPage(json: try Self.json(pageName, in: archive))

        if archive["metadata.json"] != nil, let json = try? Self.json("metadata.json", in: archive) {
            metadata = SnagxMetadata(json: json)
        } else {
            metadata = SnagxMetadata()
        }

        flattenedImageData = archive[Self.flattenedEntryName] != nil
            ? try Self.data(Self.flattenedEntryName, in: archive)
            : nil

        if contents == .all || flattenedImageData == nil, let name = page.backgroundImageName, archive[name] != nil {
            rawImageData = try Self.data(name, in: archive)
        } else {
            rawImageData = nil
        }

        guard flattenedImageData != nil || rawImageData != nil else { throw SnagxError.noImage }

        if flattenedImageData != nil {
            renderStatus = .flattened
        } else {
            renderStatus = page.hasEdits ? .unsafeRaw : .equivalentRaw
        }
    }

    public var hasRawImage: Bool { rawImageData != nil }

    /// Decodes the requested variant. `.flattened` falls back to the raw image when Snagit's
    /// flattened render is missing; check `renderStatus` for whether that is safe.
    public func image(_ variant: ImageVariant = .flattened) throws -> CGImage {
        switch variant {
        case .flattened:
            if let flattenedImageData {
                return try Self.decode(flattenedImageData, name: Self.flattenedEntryName)
            }
            guard let rawImageData else { throw SnagxError.noImage }
            return try Self.decode(rawImageData, name: page.backgroundImageName ?? "image")
        case .raw:
            guard let rawImageData else { throw SnagxError.rawImageUnavailable }
            return try Self.decode(rawImageData, name: page.backgroundImageName ?? "image")
        }
    }

    /// Decodes a downsampled flattened image whose longest side is at most `maxPixelSize`.
    public func flattenedThumbnail(maxPixelSize: Int) throws -> CGImage {
        guard let data = flattenedImageData ?? rawImageData,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { throw SnagxError.noImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SnagxError.imageDecodeFailed(Self.flattenedEntryName)
        }
        return image
    }

    /// Pixels per point of `image`, used for 1x export and for displaying at the captured size.
    public func pixelScale(of image: CGImage) -> CGFloat {
        pixelScale(pixelWidth: image.width)
    }

    /// Pixels per point for an image `pixelWidth` pixels wide.
    public func pixelScale(pixelWidth: Int) -> CGFloat {
        let fromCanvas = page.canvasSize.map { CGFloat(pixelWidth) / $0.width }
        let fromDPI = page.dpiScale.map { CGFloat($0) }
        // The flattened render matches the canvas; raw images may be larger or smaller than the canvas.
        if let fromCanvas, let fromDPI, abs(fromCanvas - fromDPI) < 0.05 { return fromDPI }
        return max(fromDPI ?? fromCanvas ?? 1, 1)
    }

    /// The encoded image shown for the flattened variant, with its type and size in points,
    /// read without decoding the pixels.
    public func flattenedImageInfo() -> (data: Data, type: UTType, pointSize: CGSize)? {
        guard let data = flattenedImageData ?? rawImageData,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let scale = pixelScale(pixelWidth: width)
        return (data, type, CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    }

    /// Human-readable key/value pairs for inspectors and `--info` output.
    public func info(for image: CGImage? = nil) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append((label, value)) }
        }
        add("Application", [metadata.appName, metadata.appVersion].compactMap { $0 }.joined(separator: " "))
        add("Window", metadata.windowName)
        add("Captured", metadata.captureDate?.formatted(date: .abbreviated, time: .standard))
        if let image {
            add("Pixels", "\(image.width) × \(image.height)")
        }
        if let canvas = page.canvasSize {
            add("Canvas", "\(Int(canvas.width)) × \(Int(canvas.height)) pt")
        }
        add("DPI", page.dpi.map { String(Int($0)) })
        add("Annotations", page.hasEdits ? "\(page.annotationCount) objects, \(page.effectCount) effects" : "None")
        let rendering = switch renderStatus {
        case .flattened: "Flattened by Snagit"
        case .equivalentRaw: "Original (no edits)"
        case .unsafeRaw: "Original – edits not rendered"
        }
        add("Rendering", rendering)
        add("System", metadata.operatingSystemVersion)
        add("Snagit", page.softwareVersion)
        add("Tags", metadata.tags.joined(separator: ", "))
        if pageCount > 1 { add("Pages", "\(pageCount) (showing first)") }
        return rows
    }

    // MARK: - Archive helpers

    private static func pageNames(in archive: Archive) throws -> [String] {
        if archive["index.json"] != nil {
            let index = try json("index.json", in: archive)
            let pages = (index["Pages"] as? [Any])?.compactMap { $0 as? String } ?? []
            if !pages.isEmpty { return pages }
        }
        // Fallback for archives without a usable index: any page document.
        return archive
            .map(\.path)
            .filter { $0.hasPrefix("{") && $0.hasSuffix(".json") && !$0.hasSuffix(".backup.json") }
            .sorted()
    }

    private static func json(_ name: String, in archive: Archive) throws -> [String: Any] {
        let data = try data(name, in: archive)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SnagxError.invalidJSON(name)
        }
        return object
    }

    private static func data(_ name: String, in archive: Archive) throws -> Data {
        guard let entry = archive[name] else { throw SnagxError.missingEntry(name) }
        guard UInt64(entry.uncompressedSize) <= maxEntrySize else { throw SnagxError.entryTooLarge(name) }
        var data = Data(capacity: Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry) { data.append($0) }
        } catch {
            throw SnagxError.missingEntry(name)
        }
        return data
    }

    static func decode(_ data: Data, name: String) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw SnagxError.imageDecodeFailed(name) }
        return image
    }
}
