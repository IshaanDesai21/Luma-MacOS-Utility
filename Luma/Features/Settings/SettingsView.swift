import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Toggle("Always open Luma on Settings", isOn: $settings.launchOnSettings)
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Hide Dynamic Island") {
                    ShortcutRecorder(shortcut: $settings.islandHideShortcut)
                }
                LabeledContent("Mute / Unmute Microphone") {
                    ShortcutRecorder(shortcut: $settings.micMuteShortcut)
                }
            }

            Section("Liquid Glass") {
                Picker("Intensity", selection: $settings.glassIntensity) {
                    ForEach(AppSettings.GlassIntensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Animation Speed") {
                Slider(value: $settings.animationSpeed, in: 0.5...1.5, step: 0.1) {
                    Text("Animation Speed")
                } minimumValueLabel: {
                    Text("Slow").font(.caption2).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Fast").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
