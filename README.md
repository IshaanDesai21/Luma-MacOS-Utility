# Luma

A native macOS utility platform built with SwiftUI + AppKit, MVVM, `@Observable`,
and async/await. Targets **macOS 15+**, Apple Silicon. No Electron / web tech.

Everything type-checks against the macOS SDK (`swiftc -typecheck`, Swift 5 mode,
0 errors / 0 warnings). A full compile + run still needs Xcode (see below).

## Download & Install

Grab the latest **`Luma.dmg`** from the [Releases](../../releases) page, open it,
and drag **Luma** into **Applications**.

First launch (the app isn't notarized, so macOS Gatekeeper guards it):

1. Double-click Luma → macOS says it can't verify the developer.
2. Open **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway** next to Luma. (On older macOS you can right-click Luma → **Open**.)
3. If it says *"Luma is damaged"*, the download was quarantined — run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Luma.app
   ```

Luma will ask for **Automation** permission the first time it reads Spotify, and
it needs to be **outside the sandbox** (it is) to switch the Dock.

## Build & Run (from source)

```bash
open Luma.xcodeproj      # select the "Luma" scheme → ⌘R
```

Requires **Xcode 26+** (Luma uses the macOS 26 Liquid Glass API, guarded so the
built app still runs on macOS 15).

## Package a DMG

```bash
./scripts/build-dmg.sh   # → build/Luma.dmg
```

## Publish a release

Tag a version and let CI build + attach the DMG automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The [`release`](.github/workflows/release.yml) workflow builds the DMG and
publishes it to a GitHub Release. (The runner needs Xcode 26 for the Liquid
Glass API; until GitHub's images ship it, build locally and upload manually:
`gh release create v1.0.0 build/Luma.dmg --generate-notes`.)

### Signing / notarization (optional, removes the Gatekeeper prompt)

The DMG ships **ad-hoc signed**, so downloaders must approve it once (above).
To make it open with no prompt, sign with a **Developer ID** (paid Apple
Developer account) and notarize:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" build/dmg/Luma.app
xcrun notarytool submit build/Luma.dmg --apple-id you@example.com \
  --team-id TEAMID --password <app-specific-password> --wait
xcrun stapler staple build/Luma.dmg
```

## Features

- **Workspace** — any number of Dock layouts, saved as a snapshot of the live
  Dock *or* composed manually from an app picker with a live Dock preview.
- **Dock** — toggle the real `com.apple.dock` settings (autohide, magnification,
  size, position, minimize effect, recents, …).
- **Dynamic Island** — a floating notch overlay that tucks away and drops down
  when the cursor reaches the top of the screen; peeks while music plays.
- **Modules** — a modular platform. Each utility is a `Module` that can surface
  itself in the Menu Bar, Touch Bar, Dynamic Island, and Sidebar. The Modules
  page toggles each location per module, instantly.
- **Menu Bar** — collapsed mode (one Luma icon → Liquid Glass popover) or an
  individual status item per enabled module.
- **Touch Bar** — auto-populated from enabled modules (visible on Touch Bar Macs
  and Xcode's Window ▸ Touch Bar simulator). Includes a custom microphone toggle
  with CoreAudio state-sync and a native "Mic Muted / Unmuted" HUD.
- **Liquid Glass intensity**, animation speed, appearance, launch-at-login.

### Modules included

Clock · Calendar · Timer · Spotify · Microphone · Battery · CPU · Memory ·
Network · Brightness · Volume · Media Controls · Emoji · Mission Control ·
Launchpad · Lock Screen · Sleep · Focus.

## Adding a module

1. Create `Features/Modules/<Name>/<Name>Module.swift` conforming to `Module`
   (subclass `ModuleObject` for services + `@objc` actions).
2. Add one line to `ModuleManager.registerModules`.

That's it — surfacing is driven polymorphically through the protocol, so no
switch statements or manager edits are needed.

## Architecture

```
Luma/
  App/            LumaApp, AppDelegate, AppModel, RootView, SidebarItem
  Managers/       ModuleManager, MenuBarManager, TouchBarManager, DynamicIslandManager
  Features/
    Workspace/    Dock switching + manual builder + preview
    Dock/         com.apple.dock toggles
    DynamicIsland/Floating overlay views
    MenuBar/      Collapsed popover
    Modules/<Name>/  one folder per module
    Settings/     Settings + Modules pages
  Services/       Dock, Spotify, System (CoreAudio, brightness, monitor), Window, HUD, catalog
  Models/         Module, ModuleLocation, ModuleConfiguration, Workspace, Track, AppSettings, …
  Utilities/      ModuleObject, TouchBar/MenuBar components, LaunchAtLogin, ProcessRunner
  Resources/      Assets.xcassets (generated app icon)
```

## Permissions & notes

- **Not sandboxed** (`Luma.entitlements`) so it can replace the Dock plist,
  run `killall Dock` / `pmset`, and use DisplayServices for brightness.
- **Automation (Spotify)** prompts on first playback read/control.
- **Microphone mute** uses CoreAudio; devices without a settable hardware mute
  fall back to zeroing input volume.
- **Brightness** loads DisplayServices at runtime; unavailable on some external
  displays.
- The app icon is generated by `Tools/GenerateIcon.swift` (`swift Tools/GenerateIcon.swift`);
  `Luma-Logo-1024.png` is a standalone copy you can upload.
```
