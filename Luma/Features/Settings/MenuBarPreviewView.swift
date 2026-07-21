import SwiftUI
import UniformTypeIdentifiers

/// A live menu-bar preview whose chips can be dragged to reorder and clicked to
/// edit (compact form, remove). Mirrors exactly what appears in the real menu bar.
struct MenuBarPreviewView: View {
    let moduleManager: ModuleManager
    let settings: AppSettings

    @State private var dragging: String?
    @State private var editing: String?

    var body: some View {
        let modules = moduleManager.orderedMenuBarModules()

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Menu Bar")
                    .font(.system(size: 14, weight: .semibold))
                Text("Drag to reorder · click an icon to edit it")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            previewStrip(modules)

            if let editing, let module = moduleManager.module(id: editing) {
                editor(module, siblings: modules)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: editing)
    }

    // MARK: - Preview strip

    @ViewBuilder
    private func previewStrip(_ modules: [Module]) -> some View {
        HStack(spacing: 4) {
            if modules.isEmpty {
                Text("No modules in the menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.vertical, 4)
            } else {
                ForEach(modules, id: \.id) { module in
                    chip(module)
                        .onDrag {
                            dragging = module.id
                            return NSItemProvider(object: module.id as NSString)
                        }
                        .onDrop(of: [.plainText], delegate: ReorderDropDelegate(
                            item: module.id, dragging: $dragging, manager: moduleManager
                        ))
                        .onTapGesture {
                            editing = (editing == module.id) ? nil : module.id
                        }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .environment(\.colorScheme, .dark)
    }

    private func chip(_ module: Module) -> some View {
        let isEditing = editing == module.id
        return (module.menuBarView(compact: moduleManager.isCompact(module))
            ?? AnyView(MenuBarChip(systemImage: module.icon, text: "")))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isEditing ? 0.22 : 0.001))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(isEditing ? 0.35 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(dragging == module.id ? 0.4 : 1)
    }

    // MARK: - Editor

    private func editor(_ module: Module, siblings: [Module]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: module.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22)
                Text(module.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    editing = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Toggle(isOn: Binding(
                get: { moduleManager.isCompact(module) },
                set: { moduleManager.setCompact($0, for: module) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Compact (icon only)").font(.system(size: 12))
                    Text("Hides the label so it takes less room.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    move(module, in: siblings, by: -1)
                } label: {
                    Label("Move left", systemImage: "arrow.left")
                }
                .disabled(index(of: module, in: siblings) == 0)

                Button {
                    move(module, in: siblings, by: 1)
                } label: {
                    Label("Move right", systemImage: "arrow.right")
                }
                .disabled(index(of: module, in: siblings) == siblings.count - 1)

                Spacer()

                Button(role: .destructive) {
                    moduleManager.setLocation(.menuBar, enabled: false, for: module)
                    editing = nil
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func index(of module: Module, in siblings: [Module]) -> Int {
        siblings.firstIndex { $0.id == module.id } ?? 0
    }

    private func move(_ module: Module, in siblings: [Module], by delta: Int) {
        var ids = siblings.map(\.id)
        guard let from = ids.firstIndex(of: module.id) else { return }
        let to = from + delta
        guard ids.indices.contains(to) else { return }
        ids.swapAt(from, to)
        moduleManager.setMenuBarOrder(ids)
    }
}

/// Live hover-reordering for the horizontal preview: as the dragged chip passes
/// over another, the order is updated immediately.
private struct ReorderDropDelegate: DropDelegate {
    let item: String
    @Binding var dragging: String?
    let manager: ModuleManager

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item else { return }
        var ids = manager.orderedMenuBarModules().map(\.id)
        guard let from = ids.firstIndex(of: dragging),
              let to = ids.firstIndex(of: item) else { return }
        guard from != to else { return }
        ids.remove(at: from)
        ids.insert(dragging, at: to)
        manager.setMenuBarOrder(ids)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
