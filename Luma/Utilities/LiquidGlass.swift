import SwiftUI

extension View {
    /// Applies real Liquid Glass on macOS 26+, falling back to a native material
    /// on macOS 14/15. `level` runs 0 to 1: near-invisible water glass through
    /// to fully frosted.
    func liquidGlass(in shape: some Shape, level: Double) -> some View {
        background {
            LiquidGlassSurface(shape: shape, level: level)
        }
    }
}

/// The layered glass backing, driven by one continuous knob:
/// - at the low end the glass base itself fades toward pure transparency, so
///   fully "liquid" is barely-there water with just refraction hints,
/// - the clear glass variant is used through the lower half,
/// - a milky frost scrim fades in continuously on top, so the far end reads as
///   properly frosted. Every position of the slider looks distinct.
struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    let level: Double

    private var clamped: Double { min(max(level, 0), 1) }

    /// Below 0.35 the whole glass layer fades out, down to 12% at fully liquid.
    private var baseOpacity: Double {
        clamped >= 0.35 ? 1 : 0.12 + (clamped / 0.35) * 0.88
    }

    /// Frost only begins past the lower quarter; up to 0.45 white at the top.
    private var frostOpacity: Double {
        max(0, clamped - 0.25) / 0.75 * 0.45
    }

    var body: some View {
        ZStack {
            glassBase.opacity(baseOpacity)
            shape.fill(.white.opacity(frostOpacity))
        }
    }

    @ViewBuilder
    private var glassBase: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(clamped < 0.5 ? .clear : .regular, in: shape)
        } else {
            shape.fill(.clear).background(fallbackMaterial, in: shape)
        }
    }

    private var fallbackMaterial: Material {
        switch clamped {
        case ..<0.35: return .ultraThinMaterial
        case ..<0.55: return .thinMaterial
        case ..<0.75: return .regularMaterial
        default: return .thickMaterial
        }
    }
}
