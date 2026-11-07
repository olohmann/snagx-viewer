import AppKit
import SnagxKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    let document: SnagxDocument
    let fileURL: URL?

    @State private var variant: ImageVariant = .flattened
    @State private var images: [ImageVariant: CGImage] = [:]
    @State private var loadError: String?
    /// `nil` = zoom to fit.
    @State private var zoom: CGFloat?
    @State private var viewportSize: CGSize = .zero
    @State private var showInspector = true
    @State private var showExportSheet = false
    @State private var exportVariant: ImageVariant = .flattened
    @State private var pendingExport = false
    @State private var exportFile: ExportedImage?
    @State private var exportName = ""
    @State private var exportType: UTType = .png
    @State private var showFileExporter = false
    @State private var errorMessage: String?

    private static let zoomLevels: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    private var image: CGImage? { images[variant] }

    private var pixelScale: CGFloat {
        image.map { document.pixelScale(of: $0) } ?? 1
    }

    private var pointSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
    }

    private var fitScale: CGFloat {
        guard pointSize.width > 0, pointSize.height > 0, viewportSize.width > 0 else { return 1 }
        return min(viewportSize.width / pointSize.width, viewportSize.height / pointSize.height, 1)
    }

    private var effectiveZoom: CGFloat { zoom ?? fitScale }

    var body: some View {
        // A fixed side panel instead of `.inspector`, whose floating glass column lets the
        // scrolling image draw underneath it and overlaps the scroll bars.
        HStack(spacing: 0) {
            imageColumn
            if showInspector {
                Divider()
                InspectorView(document: document, image: image)
                    .transition(.move(edge: .trailing))
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .toolbar { toolbar }
        .focusedSceneValue(\.captureActions, CaptureActions(
            export: { beginExport() },
            copy: { copyImage() },
            zoom: { apply($0) }
        ))
        .task { await loadImages() }
        .dropDestination(for: URL.self) { urls, _ in
            openDocuments(urls)
        }
        .sheet(isPresented: $showExportSheet, onDismiss: finishExportSheet) {
            ExportSheet(rawAvailable: document.hasRawImage, variant: $exportVariant) { confirmed in
                pendingExport = confirmed
                showExportSheet = false
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: exportFile, contentType: exportType,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            exportFile = nil
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var imageColumn: some View {
        VStack(spacing: 0) {
            if variant == .flattened, let warning = document.renderStatus.warning {
                Banner(systemImage: "exclamationmark.triangle.fill", text: warning, tint: .yellow)
            }
            if variant == .raw {
                Banner(systemImage: "eye.trianglebadge.exclamationmark",
                       text: "Original capture – may show content that was redacted in Snagit.",
                       tint: .red)
            }
            content
        }
        .clipped()
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            ZoomableImageView(image: image, pointSize: pointSize, zoom: effectiveZoom) { magnification in
                zoom = clampZoom(effectiveZoom * magnification)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
        } else if let loadError {
            ContentUnavailableView("Can’t Display Capture", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if document.hasRawImage {
            ToolbarItem(placement: .principal) {
                Picker("Image", selection: $variant) {
                    ForEach(ImageVariant.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Annotated: as exported by Snagit. Original: the unredacted capture.")
            }
        }
        ToolbarItemGroup {
            ControlGroup {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { apply(.zoomOut) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { apply(.zoomIn) }
            }
            Menu {
                Button("Zoom to Fit") { apply(.fit) }
                Button("Actual Size") { apply(.actualSize) }
                Divider()
                ForEach(Self.zoomLevels, id: \.self) { level in
                    Button("\(Int((level * 100).rounded()))%") { zoom = level }
                }
            } label: {
                Text("\(Int((effectiveZoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 44)
            }
            .help("Zoom")
        }
        ToolbarItemGroup {
            Button("Copy Image", systemImage: "doc.on.doc") { copyImage() }
                .help("Copy the image to the clipboard (⇧⌘C)")
                .disabled(image == nil)
            Button("Export…", systemImage: "square.and.arrow.up") { beginExport() }
                .help("Export as PNG or JPEG (⌘E)")
                .disabled(image == nil)
            Button("Inspector", systemImage: "info.circle") { withAnimation { showInspector.toggle() } }
                .help("Show capture details")
        }
    }

    // MARK: - Actions

    private func loadImages() async {
        let document = document
        do {
            let flattened = try await Task.detached(priority: .userInitiated) {
                try document.image(.flattened)
            }.value
            images[.flattened] = flattened
            if document.hasRawImage {
                images[.raw] = try? await Task.detached(priority: .utility) {
                    try document.image(.raw)
                }.value
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func apply(_ action: ZoomAction) {
        switch action {
        case .fit:
            zoom = nil
        case .actualSize:
            zoom = 1
        case .zoomIn:
            zoom = Self.zoomLevels.first { $0 > effectiveZoom + 0.001 } ?? Self.zoomLevels.last
        case .zoomOut:
            zoom = Self.zoomLevels.last { $0 < effectiveZoom - 0.001 } ?? Self.zoomLevels.first
        }
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.zoomLevels.first!), Self.zoomLevels.last!)
    }

    private func copyImage() {
        guard let image else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize
        let nsImage = NSImage(size: pointSize)
        nsImage.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func beginExport() {
        guard image != nil else { return }
        exportVariant = variant
        pendingExport = false
        showExportSheet = true
    }

    private func finishExportSheet() {
        guard pendingExport else { return }
        pendingExport = false
        let options = ExportPreferences.shared.options(variant: exportVariant)
        do {
            let image = try SnagxExporter.image(from: document, options: options)
            let scale = options.scale == .native ? document.pixelScale(of: image) : 1
            exportFile = ExportedImage(data: try SnagxExporter.encode(image, format: options.format, pixelScale: scale))
            exportType = options.format.contentType
            let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Capture"
            exportName = base + options.fileNameSuffix
            showFileExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDocuments(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == SnagxFileCollector.fileExtension {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }
}

private struct Banner: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.18))
            .overlay(alignment: .bottom) { Divider() }
    }
}
