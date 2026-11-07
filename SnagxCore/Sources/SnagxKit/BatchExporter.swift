import Foundation

public enum SnagxFileCollector {
    public static let fileExtension = "snagx"

    /// Expands files and folders into a sorted, de-duplicated list of `.snagx` files.
    public static func collect(_ urls: [URL], recursive: Bool) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        func append(_ url: URL) {
            let url = url.standardizedFileURL
            if url.pathExtension.lowercased() == fileExtension, seen.insert(url.path).inserted {
                result.append(url)
            }
        }
        let fileManager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                append(url)
                continue
            }
            if recursive {
                let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let child = enumerator?.nextObject() as? URL {
                    append(child)
                }
            } else {
                let children = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                     options: [.skipsHiddenFiles])) ?? []
                children.forEach(append)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

public struct BatchItemResult: Sendable, Identifiable {
    public enum Outcome: Sendable {
        case exported(output: URL, warning: String?)
        case failed(String)
    }

    public var id: URL { source }
    public let source: URL
    public let outcome: Outcome

    public var isFailure: Bool {
        if case .failed = outcome { return true }
        return false
    }

    public var warning: String? {
        if case .exported(_, let warning) = outcome { return warning }
        return nil
    }
}

public struct BatchSummary: Sendable, Equatable {
    public var exported = 0
    public var warnings = 0
    public var failed = 0

    public init(_ results: [BatchItemResult]) {
        for result in results {
            switch result.outcome {
            case .exported(_, let warning):
                exported += 1
                if warning != nil { warnings += 1 }
            case .failed:
                failed += 1
            }
        }
    }
}

public struct BatchExporter: Sendable {
    public var options: ExportOptions
    /// `nil` writes next to each source file.
    public var outputDirectory: URL?
    public var overwrite: Bool
    public var maxConcurrency: Int

    public init(options: ExportOptions, outputDirectory: URL? = nil, overwrite: Bool = false,
                maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.options = options
        self.outputDirectory = outputDirectory
        self.overwrite = overwrite
        self.maxConcurrency = max(1, maxConcurrency)
    }

    /// Exports all files; `progress` is called once per finished file (in completion order).
    public func run(_ files: [URL], progress: @escaping @Sendable (BatchItemResult) -> Void = { _ in }) async -> [BatchItemResult] {
        // Output names are reserved serially so concurrent exports never pick the same unique name.
        let reservations = NameReservations()
        return await withTaskGroup(of: (Int, BatchItemResult).self) { group in
            var results = [BatchItemResult?](repeating: nil, count: files.count)
            var next = 0
            func schedule() {
                guard next < files.count else { return }
                let index = next
                let source = files[index]
                next += 1
                group.addTask {
                    let result = exportOne(source, reservations: reservations)
                    progress(result)
                    return (index, result)
                }
            }
            for _ in 0..<min(maxConcurrency, files.count) { schedule() }
            while let (index, result) = await group.next() {
                results[index] = result
                if Task.isCancelled { group.cancelAll() } else { schedule() }
            }
            return results.compactMap { $0 }
        }
    }

    private func exportOne(_ source: URL, reservations: NameReservations) -> BatchItemResult {
        do {
            let contents: SnagxDocument.Contents = options.variant == .raw ? .all : .flattenedOnly
            let document = try SnagxDocument(url: source, contents: contents)
            let directory = outputDirectory ?? source.deletingLastPathComponent()
            let output = reservations.reserve(source: source, in: directory, options: options, overwrite: overwrite)
            let warning = try SnagxExporter.export(document, options: options, to: output)
            return BatchItemResult(source: source, outcome: .exported(output: output, warning: warning))
        } catch {
            return BatchItemResult(source: source, outcome: .failed(error.localizedDescription))
        }
    }
}

/// Hands out output names so that files written in the same run never collide with each other,
/// nor (unless overwriting) with existing files.
private final class NameReservations: @unchecked Sendable {
    private let lock = NSLock()
    /// Lowercased paths: default APFS volumes are case-insensitive.
    private var reserved = Set<String>()

    func reserve(source: URL, in directory: URL, options: ExportOptions, overwrite: Bool) -> URL {
        lock.withLock {
            let url = SnagxExporter.outputURL(for: source, in: directory, options: options) { candidate in
                reserved.contains(candidate.path.lowercased())
                    || (!overwrite && FileManager.default.fileExists(atPath: candidate.path))
            }
            reserved.insert(url.path.lowercased())
            return url
        }
    }
}
