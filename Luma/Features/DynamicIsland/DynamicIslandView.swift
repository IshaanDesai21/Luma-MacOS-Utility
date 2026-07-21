import SwiftUI
import AppKit

/// The Dynamic Island. Renders inside a fixed transparent canvas window; this
/// view alone decides the island's size, shape, and position, so what you see
/// is exactly ``DynamicIslandModel/currentLayout`` — nothing else can stretch
/// or squash it.
///
/// At rest it's a small glass capsule pod hanging below the notch; on hover it
/// springs open into the full glass media card. Content layers are fixed at
/// their own natural sizes and crossfade while the glass container animates,
/// so nothing reflows mid-animation.
struct DynamicIslandView: View {
    @Environment(DynamicIslandModel.self) private var model
    @Environment(SpotifyService.self) private var spotify
    @Environment(AppSettings.self) private var settings

    var forcedPresentation: DynamicIslandModel.Presentation?

    @State private var pulsing = false

    private var presentation: DynamicIslandModel.Presentation {
        forcedPresentation ?? model.presentation
    }

    private var layout: DynamicIslandModel.IslandLayout {
        model.layout(for: presentation)
    }

    var body: some View {
        island
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, forcedPresentation == nil ? model.topInset : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Island container

    private var island: some View {
        let layout = layout
        let shape = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        let expanded = presentation == .expanded

        return contentLayers
            .frame(width: layout.width, height: layout.height)
            .background {
                LiquidGlassSurface(shape: shape, level: settings.glassLevel)
            }
            .clipShape(shape)
            .overlay {
                // Gentle top sheen so the glass reads as glass.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.03), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .opacity(0.5)
                .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(.white.opacity(0.16), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(expanded ? 0.30 : 0.18),
                radius: expanded ? 18 : 8,
                y: expanded ? 8 : 3
            )
            // Little bounce when the track changes or the Mac unlocks.
            .scaleEffect(pulsing || model.justUnlocked ? 1.05 : 1)
            // One spring on one geometry value — size, radius, and position all
            // animate together; the window never moves.
            .animation(settings.springAnimation, value: layout)
            .animation(.easeInOut(duration: 0.16), value: presentation)
            .animation(settings.springAnimation, value: pulsing)
            .animation(settings.springAnimation, value: model.justUnlocked)
            .onChange(of: spotify.track?.title) { old, new in
                guard settings.islandTrackPulse, old != nil, new != nil else { return }
                pulse()
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard settings.islandFileShelf else { return false }
                model.shelf.add(urls: urls)
                model.noteDrop()
                return true
            } isTargeted: { targeted in
                model.isDropTargeting = settings.islandFileShelf && targeted
            }
            .onTapGesture {
                // Click the resting pod to play/pause (buttons in the expanded
                // card take precedence over this gesture).
                guard presentation == .peek, settings.islandClickPlayPause, spotify.track != nil else { return }
                spotify.playPause()
            }
    }

    private func pulse() {
        pulsing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            pulsing = false
        }
    }

    /// Both states, each laid out at its own natural size and crossfaded, so
    /// content never reflows while the glass container resizes over it.
    private var contentLayers: some View {
        ZStack {
            peekContent
                .frame(
                    width: model.layout(for: .peek).width,
                    height: model.layout(for: .peek).height
                )
                .opacity(presentation == .peek ? 1 : 0)
            expandedContent
                .frame(
                    width: model.layout(for: .expanded).width,
                    height: model.layout(for: .expanded).height
                )
                .opacity(presentation == .expanded ? 1 : 0)
        }
    }

    // MARK: - Peek (resting pod)

    private var peekContent: some View {
        HStack(spacing: 8) {
            if model.isVolumeFlashing {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 46, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.primary)
                            .frame(width: 46 * CGFloat(model.audio.volume))
                    }
                    .animation(.easeOut(duration: 0.1), value: model.audio.volume)
            } else if model.justUnlocked {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if spotify.track != nil {
                artwork(size: 22, radius: 6)
                if settings.islandVisualizer, spotify.track?.isPlaying == true {
                    VisualizerBars()
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: spotify.track?.isPlaying ?? false)
                }
            } else if settings.islandShowClockIdle {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // iOS-style status: green dot = camera in use, orange dot = mic in
            // use, green bolt = charging.
            if hasStatusIndicators {
                HStack(spacing: 4) {
                    if settings.islandShowSensors && model.sensors.cameraActive {
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                    if settings.islandShowSensors && model.sensors.micActive {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                    }
                    if settings.islandChargingIndicator && model.sensors.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    if model.isLowBattery {
                        Image(systemName: "battery.25percent")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, isActive: true)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.25), value: hasStatusIndicators)
        .animation(.easeInOut(duration: 0.25), value: model.justUnlocked)
        .animation(.easeInOut(duration: 0.15), value: model.isVolumeFlashing)
    }

    private var volumeSymbol: String {
        switch model.audio.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private var hasStatusIndicators: Bool {
        (settings.islandShowSensors && (model.sensors.cameraActive || model.sensors.micActive))
            || (settings.islandChargingIndicator && model.sensors.isCharging)
            || model.isLowBattery
    }

    // MARK: - Expanded card

    private var expandedContent: some View {
        ZStack {
            dropZone.opacity(model.isDropTargeting ? 1 : 0)
            mediaAndShelf.opacity(model.isDropTargeting ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var dropZone: some View {
        VStack(spacing: 5) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 19, weight: .medium))
            Text("Drop to hold").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediaAndShelf: some View {
        VStack(spacing: 8) {
            mediaRow
            if settings.islandFileShelf && !model.shelf.items.isEmpty {
                shelfStrip
            }
        }
    }

    private var mediaRow: some View {
        HStack(spacing: 12) {
            artwork(size: 40, radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(spotify.track?.title ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(spotify.track?.artist ?? "Drag files here to hold them")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if settings.islandShowSeekBar {
                    SeekBar(
                        progress: spotify.track?.progress ?? 0,
                        duration: spotify.track?.duration ?? 0,
                        onSeek: { spotify.seek(to: $0) }
                    )
                    .frame(height: 11)
                    .disabled(spotify.track == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
    }

    // MARK: - Held files

    private var shelfStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.shelf.items) { item in
                    fileChip(item)
                }
            }
        }
        .frame(height: 32)
    }

    private func fileChip(_ item: FileShelf.Item) -> some View {
        HStack(spacing: 5) {
            Image(nsImage: model.shelf.icon(for: item))
                .resizable().frame(width: 18, height: 18)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: 96, alignment: .leading)
            Button { model.shelf.remove(item) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .draggable(item.url)
        .onTapGesture { model.shelf.open(item) }
        .contextMenu {
            Button("Open") { model.shelf.open(item) }
            Button("Reveal in Finder") { model.shelf.reveal(item) }
            Divider()
            Button("Remove", role: .destructive) { model.shelf.remove(item) }
        }
        .help(item.name)
    }

    // MARK: - Media controls

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton("backward.fill", size: 12) { spotify.previousTrack() }
            controlButton((spotify.track?.isPlaying ?? false) ? "pause.fill" : "play.fill", size: 15) { spotify.playPause() }
            controlButton("forward.fill", size: 12) { spotify.nextTrack() }
        }
        .opacity(spotify.track == nil ? 0.35 : 1)
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(spotify.track == nil)
    }

    // MARK: - Visualizer

    /// Little animated equalizer bars for the pod — smooth, deterministic
    /// sine-driven motion (no audio tap needed).
    private struct VisualizerBars: View {
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 2.5, height: height(index: index, time: t))
                    }
                }
                .frame(height: 14, alignment: .center)
            }
        }

        private func height(index: Int, time: TimeInterval) -> CGFloat {
            // Each bar oscillates at its own frequency/phase so the group
            // looks organic rather than synchronized.
            let frequencies: [Double] = [2.1, 2.9, 2.4, 3.3]
            let phases: [Double] = [0, 1.3, 2.6, 0.8]
            let wave = sin(time * frequencies[index] + phases[index])
            return 5 + CGFloat((wave + 1) / 2) * 9
        }
    }

    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.quaternary)
            .frame(width: size, height: size)
            .overlay {
                if let url = spotify.track?.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
