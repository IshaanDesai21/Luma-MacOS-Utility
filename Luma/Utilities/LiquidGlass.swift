import SwiftUI

extension View {
    /// Applies real Liquid Glass on macOS 26+, falling back to a native material
    /// on macOS 15. The chosen ``AppSettings/GlassIntensity`` drives both the
    /// blur and an intensity-scaled frost scrim so every level looks distinct
    /// (the raw `glassEffect` API otherwise renders every level identically).
    func liquidGlass(in shape: some Shape, intensity: AppSettings.GlassIntensity) -> some View {
        background {
            LiquidGlassSurface(shape: shape, intensity: intensity)
        }
    }
}

/// The layered glass backing: a blurred glass base plus a frost scrim whose
/// opacity scales with the intensity so "Clear → Frosted" is clearly visible.
struct LiquidGlassSurface<S: Shape>: View {
    let shape: S
    let intensity: AppSettings.GlassIntensity

    var body: some View {
        ZStack {
            glassBase
            shape.fill(.white.opacity(intensity.frostScrim))
        }
    }

    @ViewBuilder
    private var glassBase: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(intensity.prefersClearGlass ? .clear : .regular, in: shape)
        } else {
            shape.fill(.clear).background(intensity.material, in: shape)
        }
    }
}
