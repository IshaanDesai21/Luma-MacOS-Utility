import SwiftUI

/// A thin capsule progress indicator used inside the Dynamic Island.
struct MiniProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.secondary)
                    .frame(width: max(0, geometry.size.width * clampedProgress))
            }
        }
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}
