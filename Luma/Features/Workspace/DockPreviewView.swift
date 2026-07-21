import SwiftUI

/// A miniature Dock shelf rendering the given apps' icons.
struct DockPreviewView: View {
    let apps: [DockApp]
    var iconSize: CGFloat = 44

    @Environment(AppCatalog.self) private var catalog
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if apps.isEmpty {
                Text("No apps yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: iconSize)
                    .padding(.horizontal, 20)
            } else {
                HStack(spacing: 10) {
                    ForEach(apps) { app in
                        Image(nsImage: catalog.icon(for: app))
                            .resizable()
                            .frame(width: iconSize, height: iconSize)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background(settings.glassMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
