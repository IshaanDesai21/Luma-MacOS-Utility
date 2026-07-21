import SwiftUI

extension View {
    /// Applies real Liquid Glass on macOS 26+, falling back to a native material
    /// on macOS 15. `level` runs 0 → 1: water-clear "very liquid" glass through
    /// to fully frosted.
    func liquidGlass(in shape: some Shape, level: Double) -> some View {
        background {
            LiquidGlassSurface(shape: shape, level: level)
        }
    }
}

/// The layered glass backing, driven by one continuous knob:
/// - the glass base switches from `.clear` (liquid) to `.regular` as the level
///   rises past the low end,
/// - a milky frost scrim fades in continuously on top, so the far end reads as
///   properly frosted. Every position of the slider looks distinct.
struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    let level: Double

    private var clamped: Double { min(max(level, 0), 1) }

    /// 0 at the liquid end, up to 0.45 white at fully frosted.
    private var frostOpacity: Double { clamped * 0.45 }

    var body: some View {
        ZStack {
            glassBase
            shape.fill(.white.opacity(frostOpacity))
        }
    }

    @ViewBuilder
    private var glassBase: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(clamped < 0.2 ? .clear : .regular, in: shape)
        } else {
            shape.fill(.clear).background(fallbackMaterial, in: shape)
        }
    }

    private var fallbackMaterial: Material {
        switch clamped {
        case ..<0.25: return .ultraThinMaterial
        case ..<0.5: return .thinMaterial
        case ..<0.75: return .regularMaterial
        default: return .thickMaterial
        }
    }
}
