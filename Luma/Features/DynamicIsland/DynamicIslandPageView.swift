import SwiftUI
import AppKit

/// Sidebar page that previews the overlay, configures behaviour, and lists the
/// feature roadmap.
struct DynamicIslandPageView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "Dynamic Island",
                    subtitle: "A Liquid Glass overlay at the notch. Move the cursor to the top to reveal it."
                )

                preview

                behaviorCard(settings: settings)
                    .frame(maxWidth: 460)

                positionCard(settings: settings)
                    .frame(maxWidth: 460)

                featuresCard(settings: settings)
                    .frame(maxWidth: 460)

                if let shortcut = settings.islandHideShortcut {
                    Label("Press \(shortcut.display) to hide the island and click through.", systemImage: "keyboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(40)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Dynamic Island")
    }

    private var preview: some View {
        GeometryReader { geo in
            // Scale the (possibly large) expanded island down to fit the box so
            // big island sizes never clip the sides of the preview.
            let base = appModel.islandModel.layout(for: .expanded)
            let fit = min(1, (geo.size.width - 28) / max(base.width, 1))
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                DynamicIslandView(forcedPresentation: .expanded)
                    .allowsHitTesting(false)
                    .frame(width: base.width, height: base.height)
                    .scaleEffect(fit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: 460)
        .frame(height: 180)
    }

    private func behaviorCard(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return VStack(spacing: 0) {
            Toggle("Enable Dynamic Island", isOn: $settings.islandEnabled)
                .padding(16)
            Divider().padding(.leading, 16)

            VStack(alignment: .leading, spacing: 6) {
                Picker("Style", selection: $settings.islandStyle) {
                    ForEach(AppSettings.IslandStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.islandStyle == .notch
                     ? "Fuses with the real notch (best on notched MacBooks), boringNotch style."
                     : "A floating glass pod that hangs below the notch or top edge.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .disabled(!settings.islandEnabled)

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
                LabeledContent("Pod size", value: "\(Int(settings.islandScale * 100))%")
                Slider(value: $settings.islandScale, in: 0.8...1.4) {
                    Text("Pod size")
                } minimumValueLabel: {
                    Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Expanded size", value: "\(Int(settings.islandExpandedScale * 100))%")
                Slider(value: $settings.islandExpandedScale, in: 0.7...1.3) {
                    Text("Expanded size")
                } minimumValueLabel: {
                    Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Sizes the dropped-down card separately from the resting pod.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Artwork glow", value: settings.islandGlowAmount < 0.02 ? "Off" : "\(Int(settings.islandGlowAmount * 100))%")
                Slider(value: $settings.islandGlowAmount, in: 0...0.8) {
                    Text("Artwork glow")
                } minimumValueLabel: {
                    Text("Off").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Bright").font(.caption2).foregroundStyle(.secondary)
                }
                Text("A soft halo around the island tinted from the current album art.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Activation area", value: "\(Int(settings.islandActivationArea * 100))%")
                Slider(value: $settings.islandActivationArea, in: 0.5...2.5) {
                    Text("Activation area")
                } minimumValueLabel: {
                    Text("Small").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Large").font(.caption2).foregroundStyle(.secondary)
                }
                Text("How close the cursor must get to the notch before the island opens.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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

            featureRow(
                icon: "camera.badge.ellipsis",
                title: "Camera & mic activity",
                subtitle: "Green/orange dots in the pod while any app uses them.",
                isOn: $settings.islandShowSensors
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "bolt.fill",
                title: "Charging indicator",
                subtitle: "A green bolt while your Mac is plugged in and charging.",
                isOn: $settings.islandChargingIndicator
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "clock",
                title: "Clock when idle",
                subtitle: "Show the time in the pod when nothing is playing.",
                isOn: $settings.islandShowClockIdle
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "slider.horizontal.below.rectangle",
                title: "Seek bar",
                subtitle: "Scrub the current song from the expanded card.",
                isOn: $settings.islandShowSeekBar
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "tray.full",
                title: "File shelf",
                subtitle: "Drop files on the island to hold them for later.",
                isOn: $settings.islandFileShelf
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "music.note.list",
                title: "Pulse on track change",
                subtitle: "The pod gives a little bounce when the song changes.",
                isOn: $settings.islandTrackPulse
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "lock.open.fill",
                title: "Unlock animation",
                subtitle: "A padlock-open flash when your Mac unlocks.",
                isOn: $settings.islandUnlockGlow
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "waveform",
                title: "Music visualizer",
                subtitle: "Animated equalizer bars in the pod while music plays.",
                isOn: $settings.islandVisualizer
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "speaker.wave.2.fill",
                title: "Scroll to change volume",
                subtitle: "Scroll on the pod to adjust system volume, with a mini readout.",
                isOn: $settings.islandScrollVolume
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "playpause.fill",
                title: "Click to play / pause",
                subtitle: "Clicking the resting pod toggles playback.",
                isOn: $settings.islandClickPlayPause
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "battery.25percent",
                title: "Low battery warning",
                subtitle: "A pulsing red battery in the pod under 15% when unplugged.",
                isOn: $settings.islandLowBatteryAlert
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "circle.fill",
                title: "Solid black island",
                subtitle: "Classic iPhone look — pure black instead of Liquid Glass.",
                isOn: $settings.islandSolidBlack
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "rectangle.on.rectangle.slash",
                title: "Replace system volume and brightness overlay",
                subtitle: "Volume and brightness keys show a sleek readout in the island instead of the macOS bezel.",
                isOn: $settings.islandSystemHUD
            )
            if settings.islandSystemHUD, appModel.mediaKeyInterceptor?.isActive != true {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seeing two overlays? Luma can't hide the macOS one until it has Accessibility permission. Toggle Luma OFF then ON in the list below. Note: running from Xcode changes the app each build, so the grant often won't stick — install the built app for this to work reliably.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Open Accessibility Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            Divider().padding(.leading, 52)
            featureRow(
                icon: "calendar",
                title: "Calendar",
                subtitle: "Show today's schedule beside the media card. Scroll the dates to browse other days.",
                isOn: $settings.islandShowCalendar
            )
            if settings.islandShowCalendar {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To show Google Calendar events, add your Google account in System Settings → Internet Accounts. Luma picks it up automatically — no sign-in needed here.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Open Internet Accounts") {
                            appModel.islandModel.calendar.openInternetAccounts()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            Divider().padding(.leading, 52)
            featureRow(
                icon: "arrow.down.circle",
                title: "Download indicator",
                subtitle: "A blue pulse in the pod while files are downloading.",
                isOn: $settings.islandDownloadProgress
            )
            Divider().padding(.leading, 52)
            featureRow(
                icon: "eye.slash",
                title: "Hide until hover",
                subtitle: "The island stays invisible until your cursor reaches the notch area, then the full card appears.",
                isOn: $settings.islandHiddenUntilHover
            )
        }
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func featureRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        // Explicit row layout (icon + text left, switch right) so every row
        // lines up — a Toggle's own label sizes to its content and staggers.
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
