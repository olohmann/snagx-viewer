import SwiftUI

/// Scrollable image at `zoom` × its point size, centered when smaller than the viewport.
struct ZoomableImageView: View {
    let image: CGImage
    let pointSize: CGSize
    let zoom: CGFloat
    let onMagnify: (CGFloat) -> Void

    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        let scale = zoom * magnification
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(scale >= 2 ? .none : .high)
                    .frame(width: pointSize.width * scale, height: pointSize.height * scale)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    .padding(8)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .scrollIndicators(.automatic)
        }
        .background(.background.secondary)
        .gesture(
            MagnifyGesture()
                .updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in onMagnify(value.magnification) }
        )
        .accessibilityLabel("Capture image")
    }
}
