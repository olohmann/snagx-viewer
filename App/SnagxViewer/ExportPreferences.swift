import Foundation
import Observation
import SnagxKit

enum FormatChoice: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpeg = "JPEG"

    var id: String { rawValue }
}

/// Export settings shared by single and batch export, persisted in user defaults.
/// The image variant is intentionally not persisted: every export starts from the flattened image.
@MainActor @Observable
final class ExportPreferences {
    static let shared = ExportPreferences()

    private let defaults = UserDefaults.standard

    var format: FormatChoice {
        didSet { defaults.set(format.rawValue, forKey: "exportFormat") }
    }

    /// 0...1
    var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: "jpegQuality") }
    }

    var scale: ExportScale {
        didSet { defaults.set(scale.rawValue, forKey: "exportScale") }
    }

    private init() {
        format = defaults.string(forKey: "exportFormat").flatMap(FormatChoice.init) ?? .png
        jpegQuality = defaults.object(forKey: "jpegQuality") as? Double ?? 0.9
        scale = defaults.string(forKey: "exportScale").flatMap(ExportScale.init) ?? .native
    }

    func options(variant: ImageVariant) -> ExportOptions {
        ExportOptions(
            format: format == .png ? .png : .jpeg(quality: jpegQuality),
            scale: scale,
            variant: variant
        )
    }
}

extension ImageVariant {
    var title: String {
        switch self {
        case .flattened: "Annotated"
        case .raw: "Original"
        }
    }
}

extension ExportScale {
    var title: String {
        switch self {
        case .native: "Native (Retina)"
        case .oneX: "1x"
        }
    }
}
