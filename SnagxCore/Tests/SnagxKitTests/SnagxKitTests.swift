import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SnagxKit

@Suite struct SnagxDocumentTests {
    let directory: URL

    init() throws { directory = try temporaryDirectory() }

    private func document(_ fixture: SnagxFixture, contents: SnagxDocument.Contents = .all) throws -> SnagxDocument {
        let url = directory.appendingPathComponent("\(UUID().uuidString).snagx")
        try fixture.write(to: url)
        return try SnagxDocument(url: url, contents: contents)
    }

    @Test func flattenedRenderIsPreferredOverRaw() throws {
        let doc = try document(SnagxFixture(annotations: 2))
        #expect(doc.renderStatus == .flattened)
        #expect(doc.renderStatus.warning == nil)
        let flattened = centerPixel(try doc.image(.flattened))
        let raw = centerPixel(try doc.image(.raw))
        #expect(flattened == [255, 0, 0, 255])
        #expect(raw == [0, 0, 255, 255])
    }

    @Test func missingFlattenedWithoutEditsIsEquivalentRaw() throws {
        let doc = try document(SnagxFixture(includeFlattened: false))
        #expect(doc.renderStatus == .equivalentRaw)
        #expect(doc.renderStatus.warning == nil)
        let flattened = centerPixel(try doc.image(.flattened))
        #expect(flattened == [0, 0, 255, 255])
    }

    @Test func missingFlattenedWithEditsIsUnsafe() throws {
        let doc = try document(SnagxFixture(annotations: 1, includeFlattened: false))
        #expect(doc.renderStatus == .unsafeRaw)
        #expect(doc.renderStatus.warning != nil)

        let output = directory.appendingPathComponent("out.png")
        let warning = try SnagxExporter.export(doc, options: ExportOptions(), to: output)
        #expect(warning != nil)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func flattenedOnlyWithoutBackgroundImage() throws {
        let doc = try document(SnagxFixture(includeRaw: false))
        #expect(doc.renderStatus == .flattened)
        #expect(!doc.hasRawImage)
        #expect(throws: SnagxError.rawImageUnavailable) { try doc.image(.raw) }
    }

    @Test func flattenedOnlyContentsSkipsRawImage() throws {
        #expect(try document(SnagxFixture(), contents: .flattenedOnly).rawImageData == nil)
        #expect(try document(SnagxFixture(includeFlattened: false), contents: .flattenedOnly).rawImageData != nil)
    }

    @Test func flattenedImageInfoReportsTypeAndPointSize() throws {
        let doc = try document(SnagxFixture(), contents: .flattenedOnly)
        let info = try #require(doc.flattenedImageInfo())
        #expect(info.type == .png)
        #expect(info.pointSize == CGSize(width: 40, height: 20))
    }

    @Test func archiveWithoutImagesFails() throws {
        #expect(throws: SnagxError.noImage) {
            try document(SnagxFixture(includeFlattened: false, includeRaw: false))
        }
    }

    @Test func nonArchiveFails() throws {
        let url = directory.appendingPathComponent("bogus.snagx")
        try Data("not a zip".utf8).write(to: url)
        #expect(throws: SnagxError.notAnArchive) { try SnagxDocument(url: url) }
    }

    @Test func parsesMetadataAndPage() throws {
        let doc = try document(SnagxFixture(annotations: 3))
        #expect(doc.metadata.appName == "Terminal")
        #expect(doc.metadata.windowName == "zsh")
        #expect(doc.metadata.tags == ["one", "two"])
        #expect(doc.metadata.ocrText == "hello world")
        // CaptureDate is UTC.
        #expect(doc.metadata.captureDate == Date(timeIntervalSince1970: 1_794_073_331))
        #expect(doc.page.canvasSize == CGSize(width: 40, height: 20))
        #expect(doc.page.annotationCount == 3)
        let scale = doc.pixelScale(of: try doc.image())
        #expect(scale == 2)
    }
}

@Suite struct SnagxExporterTests {
    let directory: URL

    init() throws { directory = try temporaryDirectory() }

    private func document(_ fixture: SnagxFixture) throws -> SnagxDocument {
        let url = directory.appendingPathComponent("capture.snagx")
        try fixture.write(to: url)
        return try SnagxDocument(url: url)
    }

    @Test(arguments: [(144, ExportScale.native, 80, 40), (144, .oneX, 40, 20), (72, .oneX, 40, 20)])
    func scalesToRequestedResolution(dpi: Int, scale: ExportScale, width: Int, height: Int) throws {
        let doc = try document(SnagxFixture(dpi: dpi))
        let image = try SnagxExporter.image(from: doc, options: ExportOptions(scale: scale))
        #expect(image.width == width)
        #expect(image.height == height)
    }

    @Test func jpegCompositesTransparencyOnWhite() throws {
        let clear = SnagxFixture.image(width: 4, height: 4, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
        let decoded = decode(try SnagxExporter.encode(clear, format: .jpeg(quality: 1)))
        #expect(decoded.alphaInfo == .none || decoded.alphaInfo == .noneSkipLast || decoded.alphaInfo == .noneSkipFirst)
        #expect(centerPixel(decoded).prefix(3).allSatisfy { $0 > 250 })
    }

    @Test func pngPreservesAlphaAndRecordsDPI() throws {
        let doc = try document(SnagxFixture())
        let output = directory.appendingPathComponent("out.png")
        try SnagxExporter.export(doc, options: ExportOptions(format: .png), to: output)
        let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        #expect(properties[kCGImagePropertyDPIWidth] as? Double == 144)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
    }

    @Test func outputNamesAreUniqueAndSuffixed() throws {
        let source = URL(fileURLWithPath: "/x/capture.snagx")
        let options = ExportOptions(format: .jpeg(quality: 0.9), scale: .oneX, variant: .raw)
        let first = SnagxExporter.outputURL(for: source, in: directory, options: options, overwrite: false)
        #expect(first.lastPathComponent == "capture-raw@1x.jpg")
        try Data().write(to: first)
        #expect(SnagxExporter.outputURL(for: source, in: directory, options: options, overwrite: false)
            .lastPathComponent == "capture-raw@1x 2.jpg")
        #expect(SnagxExporter.outputURL(for: source, in: directory, options: options, overwrite: true) == first)
    }
}

@Suite struct BatchExporterTests {
    @Test func exportsFoldersAndClassifiesResults() async throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try SnagxFixture().write(to: root.appendingPathComponent("ok.snagx"))
        try SnagxFixture().write(to: nested.appendingPathComponent("ok.snagx"))
        try SnagxFixture(annotations: 1, includeFlattened: false).write(to: nested.appendingPathComponent("unsafe.snagx"))
        try Data("garbage".utf8).write(to: nested.appendingPathComponent("broken.snagx"))
        try Data().write(to: root.appendingPathComponent("ignored.png"))

        #expect(SnagxFileCollector.collect([root], recursive: false).count == 1)
        let files = SnagxFileCollector.collect([root, root.appendingPathComponent("ok.snagx")], recursive: true)
        #expect(files.count == 4)

        let output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let results = await BatchExporter(options: ExportOptions(), outputDirectory: output).run(files)
        #expect(BatchSummary(results) == {
            var summary = BatchSummary([])
            summary.exported = 3
            summary.warnings = 1
            summary.failed = 1
            return summary
        }())
        // Two sources named ok.snagx must not overwrite each other.
        let written = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        #expect(written == ["ok 2.png", "ok.png", "unsafe.png"])
    }

    @Test func neverOverwritesExistingOrCaseVariantNames() async throws {
        let root = try temporaryDirectory()
        let output = root.appendingPathComponent("out")
        for folder in ["a", "b", "c", "out"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let sources = [
            root.appendingPathComponent("a/Shot.snagx"),
            root.appendingPathComponent("b/Shot.snagx"),
            root.appendingPathComponent("c/shot.snagx"),
        ]
        for source in sources { try SnagxFixture().write(to: source) }
        let existing = output.appendingPathComponent("Shot 2.png")
        try Data("keep".utf8).write(to: existing)

        let results = await BatchExporter(options: ExportOptions(), outputDirectory: output, maxConcurrency: 1).run(sources)
        #expect(BatchSummary(results).exported == 3)
        let outputs = Set(results.compactMap { result -> String? in
            if case .exported(let url, _) = result.outcome { return url.lastPathComponent.lowercased() }
            return nil
        })
        #expect(outputs.count == 3)
        #expect(!outputs.contains("shot 2.png"))
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }
}
