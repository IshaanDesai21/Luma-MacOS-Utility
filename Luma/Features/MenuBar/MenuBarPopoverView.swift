import SwiftUI

/// Contents of the collapsed menu-bar popover: every enabled menu-bar module,
/// stacked, on a Liquid Glass background.
struct MenuBarPopoverView: View {
    let moduleManager: ModuleManager
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars")
                Text("Luma")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            let modules = moduleManager.modules(for: .menuBar)
            if modules.isEmpty {
                Text("No menu-bar modules enabled")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    moduleRow(module)
                    if index != modules.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .frame(width: 300)
        .background(settings.glassMaterial)
    }

    @ViewBuilder
    private func moduleRow(_ module: Module) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            if let content = module.menuBarPopover() ?? module.menuBarView() {
                content
            } else {
                Text(module.name).font(.system(size: 13))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
