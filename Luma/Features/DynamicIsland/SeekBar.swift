import SwiftUI

/// A thin progress bar you can tap or drag to seek within the track. The filled
/// portion is tinted (e.g. from the album artwork) so it matches the cover.
struct SeekBar: View {
    let progress: Double
    let duration: TimeInterval
    var tint: Color = .secondary
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let fraction = clamp(dragFraction ?? progress)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(tint).frame(width: geometry.size.width * fraction, height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = clamp(value.location.x / geometry.size.width)
                    }
                    .onEnded { value in
                        let target = clamp(value.location.x / geometry.size.width)
                        dragFraction = nil
                        if duration > 0 { onSeek(target * duration) }
                    }
            )
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
