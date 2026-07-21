import Foundation

/// A Dynamic Island capability. Version 1 ships Now Playing; the rest are shown
/// as a roadmap of options that can be enabled in future releases.
struct DynamicIslandFeature: Identifiable {
    let id: String
    let name: String
    let icon: String
    let available: Bool

    static let catalog: [DynamicIslandFeature] = [
        DynamicIslandFeature(id: "nowPlaying", name: "Now Playing", icon: "music.note", available: true),
        DynamicIslandFeature(id: "shelf", name: "File Shelf", icon: "tray.full", available: true),
        DynamicIslandFeature(id: "calendar", name: "Month Calendar", icon: "calendar", available: true),
        DynamicIslandFeature(id: "keyboard", name: "Keyboard Layout", icon: "keyboard", available: true),
        DynamicIslandFeature(id: "battery", name: "Battery & Charging", icon: "battery.100.bolt", available: true),
        DynamicIslandFeature(id: "timers", name: "Timers & Stopwatch", icon: "timer", available: true),
        DynamicIslandFeature(id: "clipboard", name: "Clipboard History", icon: "doc.on.clipboard", available: true),
        DynamicIslandFeature(id: "downloads", name: "Downloads", icon: "arrow.down.circle", available: true),
        DynamicIslandFeature(id: "visualizer", name: "Music Visualizer", icon: "waveform", available: false),
        DynamicIslandFeature(id: "airdrop", name: "AirDrop Zone", icon: "dot.radiowaves.right", available: false),
        DynamicIslandFeature(id: "activity", name: "Camera / Mic Activity", icon: "camera.badge.ellipsis", available: false),
        DynamicIslandFeature(id: "weather", name: "Weather", icon: "cloud.sun", available: false),
        DynamicIslandFeature(id: "hud", name: "Notch HUD (Volume / Brightness)", icon: "speaker.wave.2", available: false),
        DynamicIslandFeature(id: "faceid", name: "Unlock Animation", icon: "faceid", available: false)
    ]
}
