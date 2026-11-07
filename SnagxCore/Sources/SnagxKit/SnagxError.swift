import Foundation

public enum SnagxError: LocalizedError, Equatable, Sendable {
    case notAnArchive
    case missingEntry(String)
    case invalidJSON(String)
    case entryTooLarge(String)
    case noImage
    case imageDecodeFailed(String)
    case encodeFailed
    case rawImageUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAnArchive: "The file is not a valid Snagit capture (.snagx)."
        case .missingEntry(let name): "The capture is missing “\(name)”."
        case .invalidJSON(let name): "The capture contains invalid data in “\(name)”."
        case .entryTooLarge(let name): "The capture entry “\(name)” is too large."
        case .noImage: "The capture contains no image."
        case .imageDecodeFailed(let name): "The image “\(name)” could not be decoded."
        case .encodeFailed: "The image could not be encoded."
        case .rawImageUnavailable: "The capture has no original (unredacted) image."
        }
    }
}
