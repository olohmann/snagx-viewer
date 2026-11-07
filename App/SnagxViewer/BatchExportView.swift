import Observation
import SnagxKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class BatchExportModel {
    private(set) var inputs: [URL] = []
    private(set) var files: [URL] = []
    var recursive = true {
        didSet { refreshFiles() }
    }
    var variant: ImageVariant = .flattened
    private(set) var outputDirectory: URL?
    private(set) var results: [BatchItemResult] = []
    private(set) var isRunning = false
    private var task: Task<Void, Never>?
    /// Security-scoped URLs (from open panels) that must stay accessible while exporting.
    private var scopedURLs: [URL] = []

    var summary: BatchSummary { BatchSummary(results) }
    var canExport: Bool { !files.isEmpty && outputDirectory != nil && !isRunning }

    func add(_ urls: [URL]) {
        for url in urls where !inputs.contains(url) {
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
            inputs.append(url)
        }
        refreshFiles()
    }

    func removeAll() {
        guard !isRunning else { return }
        inputs = []
        results = []
        refreshFiles()
    }

    func setOutputDirectory(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        outputDirectory = url
    }

    func start() {
        guard canExport, let outputDirectory else { return }
        let exporter = BatchExporter(options: ExportPreferences.shared.options(variant: variant),
                                     outputDirectory: outputDirectory)
        let files = files
        results = []
        isRunning = true
        task = Task {
            let final = await exporter.run(files) { result in
                Task { @MainActor in
                    // Progress updates may arrive after completion; the final results already include them.
                    guard self.isRunning else { return }
                    self.results.append(result)
                }
            }
            results = final
            isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func refreshFiles() {
        files = SnagxFileCollector.collect(inputs, recursive: recursive)
    }

    isolated deinit {
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}

struct BatchExportView: View {
    static let windowID = "batch-export"

    @State private var model = BatchExportModel()
    @State private var showSourcePicker = false
    @State private var showOutputPicker = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            sourceList
            Divider()
            Form {
                Section("Source") {
                    Toggle("Include subfolders", isOn: $model.recursive)
                }
                Section("Output") {
                    LabeledContent("Folder") {
                        HStack {
                            Text(model.outputDirectory?.path(percentEncoded: false) ?? "None selected")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(model.outputDirectory == nil ? .secondary : .primary)
                            Button("Choose…") { showOutputPicker = true }
                                .fileImporter(isPresented: $showOutputPicker, allowedContentTypes: [.folder]) { result in
                                    if case .success(let url) = result { model.setOutputDirectory(url) }
                                }
                        }
                    }
                    ExportSettingsForm(rawAvailable: true, variant: $model.variant)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(model.isRunning)
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var sourceList: some View {
        Group {
            if model.files.isEmpty {
                ContentUnavailableView {
                    Label("Drop Captures or Folders", systemImage: "square.and.arrow.down.on.square")
                } description: {
                    Text("Drag .snagx files or folders here, or add them with the button below.")
                }
            } else {
                List(model.files, id: \.self) { file in
                    BatchRow(file: file, result: model.results.first { $0.source == file })
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.accentColor.opacity(0.12) : .clear)
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isRunning else { return false }
            model.add(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var footer: some View {
        HStack {
            Button("Add…", systemImage: "plus") { showSourcePicker = true }
                .fileImporter(isPresented: $showSourcePicker, allowedContentTypes: [.snagx, .folder],
                              allowsMultipleSelection: true) { result in
                    if case .success(let urls) = result { model.add(urls) }
                }
                .disabled(model.isRunning)
            Button("Clear") { model.removeAll() }
                .disabled(model.isRunning || model.inputs.isEmpty)
            Spacer()
            status
            if model.isRunning {
                Button("Stop") { model.cancel() }
            } else {
                Button("Export \(model.files.count) Capture\(model.files.count == 1 ? "" : "s")") { model.start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canExport)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var status: some View {
        let summary = model.summary
        if model.isRunning {
            ProgressView(value: Double(model.results.count), total: Double(max(model.files.count, 1)))
                .frame(width: 140)
        } else if !model.results.isEmpty {
            Text("\(summary.exported) exported" + (summary.warnings > 0 ? ", \(summary.warnings) with warnings" : "")
                + (summary.failed > 0 ? ", \(summary.failed) failed" : ""))
                .foregroundStyle(summary.failed > 0 ? .red : .secondary)
                .font(.callout)
        }
    }
}

private struct BatchRow: View {
    let file: URL
    let result: BatchItemResult?

    var body: some View {
        HStack {
            icon.frame(width: 18)
            VStack(alignment: .leading) {
                Text(file.lastPathComponent)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch result?.outcome {
        case nil: Image(systemName: "photo").foregroundStyle(.secondary)
        case .exported(_, nil): Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .exported(_, _?): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var detail: String? {
        switch result?.outcome {
        case nil: file.deletingLastPathComponent().path(percentEncoded: false)
        case .exported(let output, let warning): warning ?? "→ \(output.lastPathComponent)"
        case .failed(let message): message
        }
    }
}
