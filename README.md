# Luma

A native macOS utility that gives your Mac a **Dynamic Island**, a fully
customizable **menu bar**, smarter **Dock** behavior, and one-click **workspace**
switching — all in Liquid Glass. SwiftUI + AppKit, universal binary
(Apple Silicon + Intel), macOS 14 Sonoma or newer. No Electron, no web tech.

## Install

**One file.** Download **[`Luma.dmg`](../../releases/latest)** from Releases,
open it, drag **Luma** into **Applications**. That's it — launch it from
Spotlight like any app. (Prefer a bare app? Grab `Luma.zip` instead — it unzips
straight to `Luma.app`.)

First launch only — the app isn't notarized, so macOS asks once:

1. Double-click Luma → macOS says it can't verify the developer.
2. **System Settings → Privacy & Security** → click **Open Anyway**
   (or right-click Luma → **Open** → **Open**).
3. If macOS claims the app is "damaged":
   `xattr -dr com.apple.quarantine /Applications/Luma.app`

Luma walks you through a quick setup on first open. For the volume and
brightness overlay replacement, allow **Accessibility** when prompted; music
control asks for **Automation** the first time.

## Features

### Dynamic Island
A small glass pod under the notch that springs open into a full media card when
you hover near it. Everything is a toggle or slider — customize the notch to
taste:

- **Now playing** (Spotify and Apple Music): title, artist, artwork,
  next/previous, play/pause, with controls routed to whichever app is playing
- **Seek bar** — scrub the current song right from the notch
- **Two styles** — a floating glass pod, or "part of the notch" mode that fuses
  seamlessly with the physical notch (boringNotch style) on notched MacBooks
- **System overlay replacement** — any volume or brightness change makes a
  sleek readout pop out of the notch instead of the macOS bezel
- **Volume & brightness sliders** in the expanded card
- **Artwork glow** — a soft halo around the island tinted from the album art,
  with a slider for how strong it glows
- **Download indicator** — a blue pulse in the pod while files are downloading
- **Shows on every display** — the island appears under the notch (or top
  center) of all connected monitors
- **Hide until hover** — optionally keep the island invisible until the cursor
  reaches the notch, then the full card appears
- **Music visualizer** — animated equalizer bars in the pod while music plays
- **File shelf** — drop files onto the island to hold them; drag them out later
- **Camera & mic activity** — iOS-style green/orange dots when any app uses them
- **Charging indicator** — green bolt while plugged in
- **Low battery warning** — pulsing red battery under 15% when unplugged
- **Clock when idle** — show the time when nothing is playing
- **Scroll to change volume** — scroll on the pod, get a mini volume readout
- **Click to play / pause** — tap the pod to toggle playback
- **Unlock animation** — padlock-open flash when your Mac unlocks
- **Pulse on track change** — the pod bounces when the song changes
- **Solid black mode** — classic iPhone-style pure-black island instead of glass
- Sliders for **position** (vertical + horizontal), **size**, and the
  **activation area** (how close the cursor must get before it opens)
- Hold **Option** over the island to hide it and click through

### Menu Bar
A modular strip you design yourself:

- **Live preview editor** — drag chips to reorder; the real menu bar follows
- **Overflow folder** — drag modules past the divider line to tuck them
  behind a single "everything else" button
- **Compact mode** per module (icon only) to save space
- **One-click actions** — the mic icon toggles mute instantly; the language
  icon switches keyboard layout instantly (with a HUD)
- **Collapse mode** — everything behind one Luma icon and a glass popover
- **Detailed popovers** — click Memory for a live top-processes breakdown with
  per-app usage bars; the calendar opens a full month view; and more
- 13 modules: Clock · Calendar · Timer · Spotify · Microphone · Keyboard ·
  File Shelf · Battery · CPU · Memory · Network · Downloads · Clipboard

### Dock
- Toggle the real Dock settings from Luma: autohide, magnification, size,
  position, minimize effect, indicators, recents…

### Workspaces
- Save any number of Dock layouts — snapshot the live Dock or compose one in
  the visual builder (searchable app grid + live Dock preview)
- Switch the entire Dock with one click

### Everything else
- **Liquid Glass slider** — from water-clear "very liquid" to fully frosted,
  applied across the app and the island, with a live preview swatch
- First-run **setup assistant** to dial in your notch in seconds
- Global keyboard shortcuts (hide island, mute mic)
- Launch at login, animation speed, light/dark/auto appearance

## Build from source

```bash
open Luma.xcodeproj      # Xcode 26+, select "Luma" scheme → ⌘R
./scripts/build-dmg.sh   # → build/Luma.dmg + build/Luma.zip
```

Pushing to `main` auto-builds and publishes the DMG + zip to the rolling
**"Luma — latest build"** release; pushing a `v*` tag cuts a versioned release
([workflow](.github/workflows/release.yml)).

## Architecture

```
Luma/
  App/            LumaApp, AppDelegate, AppModel, RootView, SidebarItem, Onboarding
  Managers/       ModuleManager, MenuBarManager, DynamicIslandManager
  Features/
    DynamicIsland/  island view + settings page
    Settings/       Menu Bar page (preview editor), Settings page
    Dock/           Dock toggles + click-to-hide status
    Workspace/      Dock switching + visual builder
    MenuBar/        glass popover
    Modules/<Name>/ one folder per module
  Services/       WindowManager, DynamicIslandModel, Spotify, Dock, sensors, audio…
  Models/         Module, ModuleConfiguration, Workspace, AppSettings, …
  Utilities/      LiquidGlass, MenuBarChip, LaunchAtLogin, ProcessRunner
```

Adding a module: create `Features/Modules/<Name>/<Name>Module.swift` conforming
to `Module`, register it in `ModuleManager.registerModules` — done; every
surface picks it up polymorphically.

## Permissions & notes

- **Not sandboxed** so it can switch the Dock and read system state.
- **Accessibility** — required only for the volume/brightness overlay
  replacement (re-grant after replacing the app: remove the old entry in
  System Settings, then re-allow).
- **Automation (Spotify / Apple Music)** prompts on first playback read/control.
- App icon is generated by `Tools/GenerateIcon.swift`.
