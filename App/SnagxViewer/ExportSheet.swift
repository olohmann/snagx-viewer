import SnagxKit
import SwiftUI

/// Format, quality and resolution controls shared by single and batch export.
struct ExportSettingsForm: View {
    @Bindable var preferences = ExportPreferences.shared
    let rawAvailable: Bool
    @Binding var variant: ImageVariant

    var body: some View {
        Picker("Format", selection: $preferences.format) {
            ForEach(FormatChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        if preferences.format == .jpeg {
            LabeledContent("Quality") {
                HStack {
                    Slider(value: $preferences.jpegQuality, in: 0.1...1, step: 0.05)
                    Text("\(Int((preferences.jpegQuality * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        Picker("Resolution", selection: $preferences.scale) {
            ForEach(ExportScale.allCases) { Text($0.title).tag($0) }
        }

        if rawAvailable {
            Picker("Image", selection: $variant) {
                ForEach(ImageVariant.allCases) { Text($0.title).tag($0) }
            }
            if variant == .raw {
                Label("The original may show content that was redacted in Snagit.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }
}

struct ExportSheet: View {
    let rawAvailable: Bool
    @Binding var variant: ImageVariant
    let onFinish: (_ confirmed: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                ExportSettingsForm(rawAvailable: rawAvailable, variant: $variant)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { onFinish(true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 400)
    }
}
