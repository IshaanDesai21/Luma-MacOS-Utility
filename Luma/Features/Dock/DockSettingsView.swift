import SwiftUI
import ApplicationServices

/// Controls the live macOS Dock's appearance and behaviour.
struct DockSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var viewModel = DockSettingsViewModel()
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var settings = settings

        Form {
            Section {
                Toggle(isOn: $settings.dockClickToHide) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Click active app’s Dock icon to hide it")
                        Text("Hides the front app so it disappears and whatever was behind it shows; click its icon again to bring it back. Requires Accessibility permission.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.dockClickToHide {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.dockClickWatcher.isEnabled ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(model.dockClickWatcher.status)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.dockClickToHide && !accessibilityTrusted {
                    accessibilityWarning
                }
            }

            Section("Appearance") {
                Picker("Position on screen", selection: $viewModel.preferences.orientation) {
                    ForEach(DockPreferences.Orientation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading) {
                    LabeledContent("Size", value: "\(Int(viewModel.preferences.tileSize)) pt")
                    Slider(value: $viewModel.preferences.tileSize, in: 16...128)
                }

                Toggle("Magnification", isOn: $viewModel.preferences.magnification)

                VStack(alignment: .leading) {
                    LabeledContent("Magnified size", value: "\(Int(viewModel.preferences.magnifiedSize)) pt")
                    Slider(value: $viewModel.preferences.magnifiedSize, in: 16...128)
                }
                .disabled(!viewModel.preferences.magnification)
            }

            Section("Behavior") {
                Toggle("Automatically hide and show the Dock", isOn: $viewModel.preferences.autohide)
                Toggle("Animate opening applications", isOn: $viewModel.preferences.animateOpening)
                Toggle("Show indicators for open applications", isOn: $viewModel.preferences.showIndicators)
                Toggle("Show only active applications", isOn: $viewModel.preferences.showActiveOnly)
                Toggle("Show suggested and recent apps", isOn: $viewModel.preferences.showRecents)
                Toggle("Minimize windows into application icon", isOn: $viewModel.preferences.minimizeToApplication)
            }

            Section("Minimize Effect") {
                Picker("Effect", selection: $viewModel.preferences.minimizeEffect) {
                    ForEach(DockPreferences.MinimizeEffect.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Dock")
        .onAppear {
            viewModel.reload()
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    private var accessibilityWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Accessibility permission needed")
                    .font(.system(size: 12, weight: .semibold))
                Text("Luma can’t detect Dock clicks until it’s allowed under Accessibility. If you rebuilt the app, remove any old “Luma” entry there and add it again, then re-check.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Re-check") {
                        accessibilityTrusted = AXIsProcessTrusted()
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
