import Foundation

extension Bundle {
    /// The app's marketing version, e.g. "v1.2.0". Falls back gracefully when
    /// running outside a bundle (previews, tests).
    var lumaVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        return "v\(version)"
    }
}
