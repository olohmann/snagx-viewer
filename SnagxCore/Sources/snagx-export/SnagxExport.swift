import ArgumentParser
import Foundation
import SnagxKit

@main
struct SnagxExport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snagx-export",
        abstract: "Export Snagit captures (.snagx) as PNG or JPEG.",
        discussion: """
        Exports the flattened image (annotations and redactions applied) by default.
        Use --raw for the original capture; it may reveal content that was redacted in Snagit.
        """,
        version: "1.0.0"
    )

    enum Format: String, ExpressibleByArgument, CaseIterable {
        case png, jpg, jpeg
    }

    enum Scale: String, ExpressibleByArgument, CaseIterable {
        case native
        case oneX = "1x"
    }

    @Argument(help: "Files or folders to export.", completion: .file(extensions: ["snagx"]))
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output folder (default: next to each source file).", completion: .directory)
    var output: String?

    @Option(name: .shortAndLong, help: "Image format.")
    var format: Format = .png

    @Option(name: .shortAndLong, help: "JPEG quality, 0–100.")
    var quality: Int = 90

    @Option(help: "Resolution: native (e.g. 2x Retina) or 1x.")
    var scale: Scale = .native

    @Flag(help: "Export the original, unredacted capture instead of the flattened image.")
    var raw = false

    @Flag(name: .shortAndLong, help: "Search folders recursively.")
    var recursive = false

    @Flag(help: "Overwrite existing files instead of choosing a unique name.")
    var overwrite = false

    @Flag(help: "Print capture metadata instead of exporting.")
    var info = false

    @Flag(name: .long, help: "Include OCR text with --info.")
    var ocr = false

    func validate() throws {
        guard (0...100).contains(quality) else { throw ValidationError("--quality must be between 0 and 100.") }
    }

    func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let urls = inputs.map { URL(fileURLWithPath: $0, relativeTo: cwd).standardizedFileURL }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            printError("warning: \(url.path): no such file or directory")
        }
        let files = SnagxFileCollector.collect(urls, recursive: recursive)
        guard !files.isEmpty else { throw ValidationError("No .snagx files found.") }

        if info {
            try printInfo(files)
            return
        }

        var outputDirectory: URL?
        if let output {
            let directory = URL(fileURLWithPath: output, relativeTo: cwd).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            outputDirectory = directory
        }

        let options = ExportOptions(
            format: format == .png ? .png : .jpeg(quality: Double(quality) / 100),
            scale: scale == .native ? .native : .oneX,
            variant: raw ? .raw : .flattened
        )
        if raw {
            printError("note: exporting original (unredacted) captures")
        }
        let exporter = BatchExporter(options: options, outputDirectory: outputDirectory, overwrite: overwrite)
        let results = await exporter.run(files) { result in
            switch result.outcome {
            case .exported(let output, let warning):
                print("\(result.source.path) -> \(output.path)")
                if let warning { printError("warning: \(result.source.path): \(warning)") }
            case .failed(let message):
                printError("error: \(result.source.path): \(message)")
            }
        }
        let summary = BatchSummary(results)
        printError("\(summary.exported) exported, \(summary.warnings) with warnings, \(summary.failed) failed")
        if summary.failed > 0 { throw ExitCode.failure }
    }

    private func printInfo(_ files: [URL]) throws {
        var failed = false
        for (index, file) in files.enumerated() {
            if index > 0 { print() }
            print(file.path)
            do {
                let document = try SnagxDocument(url: file, contents: .flattenedOnly)
                let image = try? document.image()
                for row in document.info(for: image) {
                    print("  \(row.label): \(row.value)")
                }
                if ocr, let text = document.metadata.ocrText, !text.isEmpty {
                    print("  OCR: \(text)")
                    if document.page.hasEdits {
                        printError("note: \(file.path): OCR text comes from the original capture and may include redacted content")
                    }
                }
                if let warning = document.renderStatus.warning { printError("warning: \(file.path): \(warning)") }
            } catch {
                failed = true
                printError("error: \(file.path): \(error.localizedDescription)")
            }
        }
        if failed { throw ExitCode.failure }
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
