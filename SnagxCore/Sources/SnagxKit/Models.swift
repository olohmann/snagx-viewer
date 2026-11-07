import CoreGraphics
import Foundation

/// Capture metadata stored in `metadata.json`.
public struct SnagxMetadata: Sendable, Equatable {
    public var appName: String?
    public var appVersion: String?
    public var windowName: String?
    /// Capture time. Snagit stores it in UTC.
    public var captureDate: Date?
    /// Text recognized from the *original* capture; may include content redacted in Snagit.
    public var ocrText: String?
    public var tags: [String] = []
    public var operatingSystemVersion: String?
    public var isStepCapture = false

    public init() {}

    init(json: [String: Any]) {
        appName = json.string("AppName")
        appVersion = json.string("AppVersion")
        windowName = json.string("WindowName")
        captureDate = json.string("CaptureDate").flatMap(Self.parseDate)
        ocrText = json.string("OcrText")
        tags = (json["Tags"] as? [Any] ?? []).compactMap { tag in
            if let tag = tag as? String { return tag }
            if let tag = tag as? [String: Any] { return tag.string("Name") ?? tag.string("Tag") }
            return nil
        }
        operatingSystemVersion = json.string("OperatingSystemVersion")
        isStepCapture = json["IsStepCapture"] as? Bool ?? false
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)
    }
}

/// Canvas description from a page document (`{GUID}.json`).
public struct SnagxPage: Sendable, Equatable {
    /// Archive entry name of the raw (unannotated) capture.
    public var backgroundImageName: String?
    /// Canvas size in points.
    public var canvasSize: CGSize?
    public var dpi: Double?
    public var annotationCount = 0
    public var effectCount = 0
    public var softwareVersion: String?

    public init() {}

    init(json: [String: Any]) {
        backgroundImageName = json.string("CaptureBackgroundImage").flatMap { $0.isEmpty ? nil : $0 }
        if let width = json.double("CaptureCanvasWidth"), let height = json.double("CaptureCanvasHeight"),
           width > 0, height > 0 {
            canvasSize = CGSize(width: width, height: height)
        }
        dpi = json.double("DPI").flatMap { $0 > 0 ? $0 : nil }
        annotationCount = (json["CaptureObjects"] as? [Any])?.count ?? 0
        effectCount = (json["Effects"] as? [Any])?.count ?? 0
        softwareVersion = json.string("SoftwareVersion")
    }

    /// Whether Snagit applied anything (annotations, blur, effects) on top of the raw capture.
    public var hasEdits: Bool { annotationCount > 0 || effectCount > 0 }

    /// Pixels per point derived from the DPI (144 DPI = 2x).
    public var dpiScale: Double? { dpi.map { $0 / 72 } }
}

/// How faithfully the flattened image represents what Snagit would export.
public enum RenderStatus: Sendable, Equatable {
    /// Snagit's own full-resolution flattened render is available.
    case flattened
    /// No flattened render, but the capture has no edits, so the raw image is identical.
    case equivalentRaw
    /// No flattened render and the capture has edits: the raw image may reveal redacted content.
    case unsafeRaw

    public var warning: String? {
        switch self {
        case .flattened, .equivalentRaw: nil
        case .unsafeRaw:
            "This capture has annotations or redactions that could not be rendered. "
                + "The image shown is the original capture and may reveal redacted content."
        }
    }
}

public enum ImageVariant: String, Sendable, CaseIterable, Identifiable {
    /// What Snagit exports: annotations and redactions applied.
    case flattened
    /// The original, unredacted capture.
    case raw

    public var id: String { rawValue }
}

extension [String: Any] {
    func string(_ key: String) -> String? { self[key] as? String }

    func double(_ key: String) -> Double? {
        switch self[key] {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }
}
