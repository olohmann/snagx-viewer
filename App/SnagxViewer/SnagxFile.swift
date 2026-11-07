import SnagxKit
import SwiftUI
import UniformTypeIdentifiers

/// Read-only document wrapper for SwiftUI's `DocumentGroup`.
struct SnagxFile: FileDocument {
    static let readableContentTypes: [UTType] = [.snagx]
    static let writableContentTypes: [UTType] = []

    let document: SnagxDocument

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        document = try SnagxDocument(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

/// Encoded image handed to `fileExporter`.
struct ExportedImage: FileDocument {
    static let readableContentTypes: [UTType] = []
    static let writableContentTypes: [UTType] = [.png, .jpeg]

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
