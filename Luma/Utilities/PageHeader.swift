import SwiftUI

/// Consistent centered title + subtitle used across detail pages.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
