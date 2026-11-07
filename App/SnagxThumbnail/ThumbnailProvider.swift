import CoreGraphics
import OSLog
import QuickLookThumbnailing
import SnagxKit

/// Finder icons/thumbnails. Uses Snagit's flattened render, never the raw capture.
final class ThumbnailProvider: QLThumbnailProvider {
    private static let logger = Logger(subsystem: "com.olohmann.SnagxViewer", category: "Thumbnail")

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let document = try SnagxDocument(url: request.fileURL, contents: .flattenedOnly)
            // No thumbnail rather than leaking redacted content; Finder falls back to the file icon.
            guard document.renderStatus != .unsafeRaw else {
                handler(nil, SnagxError.noImage)
                return
            }
            let maximum = request.maximumSize
            let image = try document.flattenedThumbnail(
                maxPixelSize: Int((max(maximum.width, maximum.height) * request.scale).rounded(.up)))

            let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
            var size = maximum
            if aspect > maximum.width / maximum.height {
                size.height = (maximum.width / aspect).rounded()
            } else {
                size.width = (maximum.height * aspect).rounded()
            }
            let rect = CGRect(origin: .zero, size: size)
            handler(QLThumbnailReply(contextSize: size) { context in
                context.interpolationQuality = .high
                context.draw(image, in: rect)
                return true
            }, nil)
        } catch {
            Self.logger.error("Thumbnail failed: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }
}
