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
/// - the base is ALWAYS real Liquid Glass (transparent + blurred/refractive),
///   so the liquid end looks like Apple's clear glass panels — you see through
///   it, not a dark fill,
/// - a milky frost scrim fades in on top as the level rises, so the far end
///   reads as properly frosted. Every position looks distinct and glassy.
struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    let level: Double

    private var clamped: Double { min(max(level, 0), 1) }

    /// Frost grows from 0 (pure clear glass) to ~0.5 (milky frosted).
    private var frostOpacity: Double { clamped * 0.5 }

    var body: some View {
        ZStack {
            glassBase
            shape.fill(.white.opacity(frostOpacity))
        }
    }

    @ViewBuilder
    private var glassBase: some View {
        if #available(macOS 26.0, *) {
            // Real Apple Liquid Glass at full strength: clear (very glassy) for
            // the liquid half, regular for the frosted half. Never faded, so it
            // stays transparent/refractive instead of turning into a flat tint.
            Color.clear.glassEffect(clamped < 0.5 ? .clear : .regular, in: shape)
        } else {
            // macOS 15 fallback: a thin translucent material at the liquid end,
            // thickening toward frosted.
            shape.fill(.clear).background(fallbackMaterial, in: shape)
        }
    }

    private var fallbackMaterial: Material {
        switch clamped {
        case ..<0.35: return .ultraThinMaterial
        case ..<0.6: return .thinMaterial
        case ..<0.8: return .regularMaterial
        default: return .thickMaterial
        }
    }
}
