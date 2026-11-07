import Foundation
import OSLog
import Quartz
import SnagxKit
import UniformTypeIdentifiers

/// Quick Look (spacebar) preview. Always shows Snagit's flattened render, never the raw capture.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "com.olohmann.SnagxViewer", category: "QuickLook")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        do {
            return try makeReply(for: request.fileURL)
        } catch {
            Self.logger.error("Preview failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func makeReply(for url: URL) throws -> QLPreviewReply {
        let document = try SnagxDocument(url: url, contents: .flattenedOnly)
        let title = [document.metadata.appName, document.metadata.windowName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " – ")

        // Without Snagit's render, the only image is the raw capture, which would expose redacted content.
        guard document.renderStatus != .unsafeRaw else {
            Self.logger.info("Preview unavailable: edits not rendered")
            let html = Self.unavailableHTML(document.renderStatus.warning ?? "")
            let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 520, height: 180)) { _ in
                Data(html.utf8)
            }
            reply.stringEncoding = .utf8
            return reply
        }

        guard let info = document.flattenedImageInfo() else { throw SnagxError.noImage }
        let data = info.data
        let reply = QLPreviewReply(dataOfContentType: info.type, contentSize: info.pointSize) { _ in data }
        if !title.isEmpty { reply.title = title }
        Self.logger.info("Preview \(info.type.identifier, privacy: .public) \(Int(info.pointSize.width))x\(Int(info.pointSize.height)) pt")
        return reply
    }

    private static func unavailableHTML(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font: 13px -apple-system; margin: 24px; }
        h1 { font-size: 15px; margin: 0 0 8px; }
        </style></head><body>
        <h1>⚠️ Preview unavailable</h1>
        <p>\(escaped)</p>
        <p>Open the capture in Snagx Viewer or Snagit to view it.</p>
        </body></html>
        """
    }
}
