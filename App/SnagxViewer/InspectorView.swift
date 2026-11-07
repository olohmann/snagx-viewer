import AppKit
import SnagxKit
import SwiftUI

/// Side panel with capture details: a compact label/value grid plus the recognized (OCR) text.
struct InspectorView: View {
    static let width: CGFloat = 300

    let document: SnagxDocument
    let image: CGImage?

    /// OCR runs on the original capture, so it can contain text that was redacted in Snagit.
    @State private var revealText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                details
                if let text = document.metadata.ocrText, !text.isEmpty {
                    recognizedText(text)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Capture")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(document.info(for: image).enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .gridColumnAlignment(.trailing)
                        Text(row.value)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func recognizedText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Recognized Text")
                Spacer()
                if !document.page.hasEdits || revealText {
                    Button("Copy Text", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy recognized text")
                }
            }
            if document.page.hasEdits && !revealText {
                Label("Recognized from the original capture. It may include text that was redacted in Snagit.",
                      systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show Recognized Text") { revealText = true }
            } else {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
