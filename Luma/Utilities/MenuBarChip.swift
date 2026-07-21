import SwiftUI

/// Compact icon + text used as a module's menu-bar representation.
struct MenuBarChip: View {
    var systemImage: String?
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
            }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
    }
}

/// A titled row used inside the collapsed menu-bar popover.
struct MenuBarRow<Trailing: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
