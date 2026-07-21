import SwiftUI

/// First-run setup: a short, focused flow — welcome, dial in the notch's glass
/// and size (the two settings everyone tweaks), done. Everything else stays
/// discoverable in the app rather than crammed in here.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings

    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: customize
                default: finish
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 520, height: 480)
        .background(settings.glassMaterial)
        .interactiveDismissDisabled()
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Welcome to Luma")
                .font(.system(size: 26, weight: .bold))
            Text("A Dynamic Island for your notch, a menu bar you design yourself, and a smarter Dock — all in Liquid Glass.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    private var customize: some View {
        @Bindable var settings = settings
        return VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("Set up your notch")
                    .font(.system(size: 20, weight: .bold))
                Text("Just the essentials — everything else lives in the app.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Live island preview reflecting both sliders.
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                DynamicIslandView(forcedPresentation: .expanded)
                    .allowsHitTesting(false)
                    .scaleEffect(0.8)
            }
            .frame(height: 120)
            .padding(.horizontal, 36)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Liquid Glass")
                        .font(.system(size: 12, weight: .semibold))
                    Slider(value: $settings.glassLevel, in: 0...1) {
                        Text("Glass")
                    } minimumValueLabel: {
                        Text("Liquid").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Frosted").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Island size — \(Int(settings.islandScale * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                    Slider(value: $settings.islandScale, in: 0.8...1.4) {
                        Text("Size")
                    } minimumValueLabel: {
                        Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 48)
        }
    }

    private var finish: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're all set")
                .font(.system(size: 22, weight: .bold))
            Text("Move your cursor to the notch to open the island.\nFine-tune everything else from the sidebar whenever you like.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle("Launch Luma at login", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { settings.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .padding(.top, 8)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step == 0 {
                Button("Skip") { complete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()
            Button(step == 2 ? "Start Using Luma" : "Continue") {
                if step == 2 {
                    complete()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func complete() {
        settings.hasCompletedOnboarding = true
    }
}
