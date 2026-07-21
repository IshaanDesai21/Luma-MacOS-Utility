import SwiftUI

/// Sidebar page that previews the overlay, configures behaviour, and lists the
/// feature roadmap.
struct DynamicIslandPageView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(spacing: 28) {
                PageHeader(
                    title: "Dynamic Island",
                    subtitle: "A Liquid Glass overlay at the notch. Move the cursor to the top to reveal it."
                )

                preview

                behaviorCard(settings: settings)
                    .frame(maxWidth: 440)

                positionCard(settings: settings)
                    .frame(maxWidth: 440)

                featuresCard(settings: settings)
                    .frame(maxWidth: 440)

                if let shortcut = settings.islandHideShortcut {
                    Label("Press \(shortcut.display) to hide the island and click through.", systemImage: "keyboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dynamic Island")
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.quaternary.opacity(0.35))
            DynamicIslandView(forcedPresentation: .expanded)
                .allowsHitTesting(false)
                .frame(width: 384, height: 100)
        }
        .frame(maxWidth: 440)
        .frame(height: 150)
    }

    private func behaviorCard(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            Toggle("Enable Dynamic Island", isOn: $settings.islandEnabled)
                .padding(16)
            Divider().padding(.leading, 16)
            Toggle("Reveal on hover", isOn: $settings.islandRevealOnHover)
                .padding(16)
                .disabled(!settings.islandEnabled)
        }
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func positionCard(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Vertical", value: heightLabel(settings.islandVerticalOffset))
                Slider(value: $settings.islandVerticalOffset, in: -40...30) {
                    Text("Vertical")
                } minimumValueLabel: {
                    Text("Lower").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Higher").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Horizontal", value: horizontalLabel(settings.islandHorizontalOffset))
                Slider(value: $settings.islandHorizontalOffset, in: -500...500) {
                    Text("Horizontal")
                } minimumValueLabel: {
                    Text("Left").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Right").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Size", value: "\(Int(settings.islandScale * 100))%")
                Slider(value: $settings.islandScale, in: 0.8...1.4) {
                    Text("Size")
                } minimumValueLabel: {
                    Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .disabled(!settings.islandEnabled)
    }

    private func heightLabel(_ value: Double) -> String {
        if abs(value) < 1 { return "Default" }
        return value > 0 ? "\(Int(value)) pt higher" : "\(Int(-value)) pt lower"
    }

    private func horizontalLabel(_ value: Double) -> String {
        if abs(value) < 1 { return "Centered" }
        return value > 0 ? "\(Int(value)) pt right" : "\(Int(-value)) pt left"
    }

    private func featuresCard(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            HStack {
                Text("Features")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(Array(DynamicIslandFeature.catalog.enumerated()), id: \.element.id) { index, feature in
                featureRow(feature, settings: settings)
                if index != DynamicIslandFeature.catalog.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func featureRow(_ feature: DynamicIslandFeature, settings: AppSettings) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(feature.name)
                .font(.system(size: 13))
            Spacer()
            if feature.available {
                Label("On", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Text("Soon")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(feature.available ? 1 : 0.55)
    }
}
