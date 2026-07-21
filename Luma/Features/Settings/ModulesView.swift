import SwiftUI

/// Lists every module with instant toggles for each location it supports.
struct ModulesView: View {
    @Environment(ModuleManager.self) private var moduleManager
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PageHeader(
                    title: "Menu Bar",
                    subtitle: "Arrange the strip, tuck extras into the ⋯ folder, and choose where each module appears."
                )

                MenuBarPreviewView(moduleManager: moduleManager, settings: settings)

                menuBarModeCard
                    .frame(maxWidth: 560)

                ForEach(moduleManager.modules, id: \.id) { module in
                    moduleCard(module)
                        .frame(maxWidth: 560)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Menu Bar")
    }

    private var menuBarModeCard: some View {
        Toggle(isOn: Binding(
            get: { moduleManager.collapseMenuBar },
            set: { moduleManager.setCollapseMenuBar($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Collapse menu bar into one icon")
                Text("Off: each module gets its own menu-bar item. On: a single Luma icon opens a popover.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func moduleCard(_ module: Module) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: module.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24)
                Text(module.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { moduleManager.isEnabled(module) },
                    set: { moduleManager.setEnabled($0, for: module) }
                ))
                .labelsHidden()
            }
            .padding(16)

            Divider().padding(.leading, 52)

            VStack(spacing: 0) {
                ForEach(locations(for: module)) { location in
                    locationRow(module, location)
                    Divider().padding(.leading, 52)
                }
            }
            .disabled(!moduleManager.isEnabled(module))
            .opacity(moduleManager.isEnabled(module) ? 1 : 0.5)
        }
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func locationRow(_ module: Module, _ location: ModuleLocation) -> some View {
        Toggle(isOn: Binding(
            get: { moduleManager.config(for: module).locations.contains(location) },
            set: { moduleManager.setLocation(location, enabled: $0, for: module) }
        )) {
            Label("Show in \(location.title)", systemImage: location.symbol)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func locations(for module: Module) -> [ModuleLocation] {
        ModuleLocation.allCases.filter { module.supportedLocations.contains($0) }
    }
}
