import SnagxKit
import SwiftUI

@main
struct SnagxViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: SnagxFile.self) { configuration in
            CaptureView(document: configuration.document.document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 1100, height: 760)
        .commands { AppCommands() }

        Window("Batch Export", id: BatchExportView.windowID) {
            BatchExportView()
        }
        .defaultSize(width: 640, height: 520)
    }
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.captureActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Export…") { actions?.export() }
                .keyboardShortcut("e")
                .disabled(actions == nil)
            Button("Batch Export…") { openWindow(id: BatchExportView.windowID) }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Image") { actions?.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { actions?.zoom(.zoomIn) }
                .keyboardShortcut("+")
                .disabled(actions == nil)
            Button("Zoom Out") { actions?.zoom(.zoomOut) }
                .keyboardShortcut("-")
                .disabled(actions == nil)
            Button("Actual Size") { actions?.zoom(.actualSize) }
                .keyboardShortcut("0")
                .disabled(actions == nil)
            Button("Zoom to Fit") { actions?.zoom(.fit) }
                .keyboardShortcut("9")
                .disabled(actions == nil)
            Divider()
        }
    }
}

enum ZoomAction {
    case zoomIn, zoomOut, actualSize, fit
}

struct CaptureActions {
    var export: () -> Void
    var copy: () -> Void
    var zoom: (ZoomAction) -> Void
}

extension FocusedValues {
    @Entry var captureActions: CaptureActions?
}
