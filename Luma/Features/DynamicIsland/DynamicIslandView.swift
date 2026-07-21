import SwiftUI
import AppKit

/// The floating overlay. The window sizes the panel; this view forces its glass
/// shape to exactly the panel size (via GeometryReader) so content can never
/// overflow into a giant rectangle. Inner states crossfade.
struct DynamicIslandView: View {
    @Environment(DynamicIslandModel.self) private var model
    @Environment(SpotifyService.self) private var spotify
    @Environment(AppSettings.self) private var settings

    var forcedPresentation: DynamicIslandModel.Presentation?

    private var presentation: DynamicIslandModel.Presentation {
        forcedPresentation ?? model.presentation
    }

    var body: some View {
        island
            .padding(16)                                          // shadow margin (matches window)
            // Fill the panel with a concrete size so the glass sizes to the actual
            // (animated) window — not the inner layers' natural size — which keeps
            // the resting shape a proper pill. Only the window animates size, so
            // the glass grows symmetrically about center; SwiftUI just crossfades.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(settings.islandAnimation, value: presentation)
            .animation(settings.springAnimation, value: spotify.track)
            .animation(settings.islandAnimation, value: model.isDropTargeting)
    }

    private var island: some View {
        let shape = islandShape
        return innerLayers
            .scaleEffect(settings.islandScale)                    // render at chosen size
            // Fill the window (its animated frame is the single size source) so
            // the glass is always exactly centered and reveals in place.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .background {
                // Liquid Glass in every state — the resting pod is a small glass
                // capsule, the expanded card the same glass grown large.
                LiquidGlassSurface(shape: shape, intensity: settings.glassIntensity)
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .opacity(presentation == .hidden ? 0 : 0.35)
                .allowsHitTesting(false)
            }
            .overlay(shape.stroke(.white.opacity(presentation == .hidden ? 0 : 0.16), lineWidth: 0.6).allowsHitTesting(false))
            .shadow(color: .black.opacity(presentation == .hidden ? 0 : 0.3), radius: shadowRadius, y: shadowOffset)
            .dropDestination(for: URL.self) { urls, _ in
                model.shelf.add(urls: urls)
                model.noteDrop()
                return true
            } isTargeted: { targeted in
                model.isDropTargeting = targeted
            }
    }

    // MARK: - Inner states (crossfaded)

    // Each layer is pinned to the natural size of its own presentation — never
    // the animating outer frame — so content can't reflow (cramp then spring)
    // while the island grows. The glass container animates the size and clips
    // each layer into view; crossfade handles the swap.
    private var innerLayers: some View {
        ZStack {
            idle
                .frame(width: hiddenMetrics.width, height: hiddenMetrics.height)
                .opacity(presentation == .hidden ? 1 : 0)
            peek
                .frame(width: peekMetrics.width, height: peekMetrics.height)
                .opacity(presentation == .peek ? 1 : 0)
            expandedLayer
                .frame(width: expandedMetrics.width, height: expandedMetrics.height)
                .opacity(presentation == .expanded ? 1 : 0)
        }
    }

    private var hiddenMetrics: DynamicIslandModel.Metrics { model.metrics(for: .hidden) }
    private var peekMetrics: DynamicIslandModel.Metrics { model.metrics(for: .peek) }
    private var expandedMetrics: DynamicIslandModel.Metrics {
        var m = model.metrics(for: .expanded)
        if model.isDropTargeting || !model.shelf.items.isEmpty { m.height = 112 }
        return m
    }

    private var idle: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.black.opacity(0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var peek: some View {
        HStack(spacing: 9) {
            if spotify.track != nil {
                artwork(size: 24, radius: 6)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: spotify.track?.isPlaying ?? false)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
    }

    private var expandedLayer: some View {
        ZStack {
            dropZone.opacity(model.isDropTargeting ? 1 : 0)
            mediaAndShelf.opacity(model.isDropTargeting ? 0 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
            if !model.shelf.items.isEmpty {
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
                SeekBar(
                    progress: spotify.track?.progress ?? 0,
                    duration: spotify.track?.duration ?? 0,
                    onSeek: { spotify.seek(to: $0) }
                )
                .frame(height: 11)
                .disabled(spotify.track == nil)
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

    // MARK: - Shape metrics

    /// A capsule at rest — geometrically always a pill, no matter what size the
    /// panel gives us — and a rounded rectangle only when expanded.
    private var islandShape: AnyShape {
        presentation == .expanded
            ? AnyShape(RoundedRectangle(cornerRadius: 26 * settings.islandScale, style: .continuous))
            : AnyShape(Capsule(style: .continuous))
    }

    private var radius: CGFloat {
        switch presentation {
        case .hidden: return 4
        case .peek: return 17
        case .expanded: return 26
        }
    }

    private var shadowRadius: CGFloat {
        switch presentation {
        case .expanded: return 16
        case .peek: return 7
        case .hidden: return 0
        }
    }

    private var shadowOffset: CGFloat {
        switch presentation {
        case .expanded: return 7
        case .peek: return 3
        case .hidden: return 0
        }
    }
}
