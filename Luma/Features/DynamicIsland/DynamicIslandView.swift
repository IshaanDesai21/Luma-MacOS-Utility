import SwiftUI
import AppKit

/// The Dynamic Island. Renders inside fixed transparent canvas windows (one per
/// display); this view alone decides the island's size, shape, and position, so
/// what you see is exactly ``DynamicIslandModel/currentLayout`` — nothing else
/// can stretch or squash it.
///
/// At rest it's a small glass capsule pod hanging below the notch; on hover it
/// springs open into the full glass media card. Content layers are fixed at
/// their own natural sizes and crossfade while the glass container animates,
/// so nothing reflows mid-animation.
struct DynamicIslandView: View {
    @Environment(DynamicIslandModel.self) private var model
    @Environment(NowPlayingService.self) private var player
    @Environment(AppSettings.self) private var settings

    var forcedPresentation: DynamicIslandModel.Presentation?

    @Environment(\.colorScheme) private var contentColorScheme
    @State private var pulsing = false
    @State private var glowColor: Color?

    /// The album-art accent color (vivid), or the app accent when unknown.
    private var albumColor: Color { glowColor ?? .accentColor }

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
        let shape = islandShape(cornerRadius: layout.cornerRadius)
        let expanded = presentation == .expanded
        let tucked = forcedPresentation == nil && model.isTuckedAway
        // Notch style is always solid black so it fuses with the real notch.
        let solidBlack = settings.islandSolidBlack || model.isNotchStyle

        return contentLayers
            // Solid black content sits on black; force light-on-dark styling.
            .environment(\.colorScheme, solidBlack ? .dark : contentColorScheme)
            .frame(width: layout.width, height: layout.height)
            .background {
                if solidBlack {
                    shape.fill(.black)
                } else {
                    LiquidGlassSurface(shape: shape, level: settings.glassLevel)
                }
            }
            .clipShape(shape)
            .overlay {
                // Top sheen scales with the frost level, so the "Liquid" end of
                // the slider stays truly water-clear. None on solid black.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.03), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .opacity(solidBlack ? 0 : 0.55 * settings.glassLevel)
                .allowsHitTesting(false)
            }
            .overlay {
                shape.stroke(.white.opacity(solidBlack ? 0.10 : 0.16), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(expanded ? 0.30 : 0.18),
                radius: expanded ? 18 : 8,
                y: expanded ? 8 : 3
            )
            // Album-art glow: a soft halo tinted from the current artwork. In
            // notch style it's biased downward (and tighter) so it never bleeds
            // up over the real notch — keeping the "part of the hardware" look.
            .shadow(
                color: (glowColor ?? .clear).opacity(player.track == nil ? 0 : settings.islandGlowAmount),
                radius: model.isNotchStyle ? (expanded ? 18 : 10) : (expanded ? 26 : 16),
                y: model.isNotchStyle ? (expanded ? 20 : 12) : 4
            )
            // Little bounce when the track changes or the Mac unlocks.
            .scaleEffect(pulsing || model.justUnlocked ? 1.05 : 1)
            // Hidden-until-hover mode: invisible at rest, hover strip still live.
            .opacity(tucked ? 0 : 1)
            // One spring on one geometry value — size, radius, and position all
            // animate together; the window never moves.
            .animation(settings.springAnimation, value: layout)
            .animation(.easeInOut(duration: 0.16), value: presentation)
            .animation(.easeInOut(duration: 0.2), value: tucked)
            .animation(settings.springAnimation, value: pulsing)
            .animation(settings.springAnimation, value: model.justUnlocked)
            .onChange(of: player.track?.title) { old, new in
                guard settings.islandTrackPulse, old != nil, new != nil else { return }
                pulse()
            }
            .task(id: artworkIdentity) {
                glowColor = await Self.averageColor(url: player.track?.artworkURL, data: player.track?.artworkData)
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
                guard presentation == .peek, settings.islandClickPlayPause, player.track != nil else { return }
                player.playPause()
            }
    }

    private func pulse() {
        pulsing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            pulsing = false
        }
    }

    /// Floating style is a full rounded rectangle; notch style has a flat top
    /// (merging with the physical notch) and rounded bottom corners only.
    private func islandShape(cornerRadius: CGFloat) -> AnyShape {
        if model.isNotchStyle {
            return AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            ))
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Each layer is laid out at its natural (unscaled) size, then scaled to fit
    /// its final footprint — so shrinking never clips the album cover or content.
    private var contentLayers: some View {
        ZStack {
            // In notch style the resting tab is an empty black notch (the physical
            // notch sits over it); playing flanks it with art + visualizer.
            islandLayer(model.isNotchStyle ? AnyView(notchPeekContent) : AnyView(peekContent), .peek)
            islandLayer(AnyView(hudContent.padding(.top, model.notchClearance)), .hud)
            islandLayer(AnyView(expandedContent.padding(.top, model.notchClearance)), .expanded)
        }
    }

    /// Lays a layer out at its base size, scales it uniformly to the target, and
    /// sets the scaled footprint so it fills the glass exactly without clipping.
    private func islandLayer(_ content: AnyView, _ p: DynamicIslandModel.Presentation) -> some View {
        let base = model.baseSize(for: p)
        let scaled = model.layout(for: p)
        return content
            .frame(width: base.width, height: base.height)
            .scaleEffect(model.contentScale(for: p), anchor: .top)
            .frame(width: scaled.width, height: scaled.height)
            .opacity(presentation == p ? 1 : 0)
    }

    // MARK: - Pop-out HUD (volume / brightness)

    private var hudContent: some View {
        let isBrightness = model.isBrightnessFlashing
        let fraction = isBrightness ? CGFloat(model.brightness.brightness) : CGFloat(model.audio.volume)
        return HStack(spacing: 12) {
            Image(systemName: isBrightness ? "sun.max.fill" : volumeSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 22)
            levelBar(fraction, width: 130, height: 5)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Notch peek (art flanks the notch)

    @ViewBuilder
    private var notchPeekContent: some View {
        if player.track != nil {
            HStack(spacing: 0) {
                artwork(size: 26, radius: 6)
                    .padding(.leading, 12)
                // The physical notch occupies the middle.
                Spacer(minLength: model.notchSize.width)
                if settings.islandVisualizer, player.track?.isPlaying == true {
                    VisualizerBars(color: albumColor)
                        .padding(.trailing, 14)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(albumColor)
                        .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    // MARK: - Peek (resting pod)

    private var peekContent: some View {
        HStack(spacing: 8) {
            if model.justUnlocked {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if player.track != nil {
                artwork(size: 22, radius: 6)
                if settings.islandVisualizer, player.track?.isPlaying == true {
                    VisualizerBars(color: albumColor)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.variableColor.iterative, isActive: player.track?.isPlaying ?? false)
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
            // use, green bolt = charging, blue arrow = downloading.
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
                    if settings.islandDownloadProgress && model.downloads.activeCount > 0 {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, isActive: true)
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
    }

    private func levelBar(_ fraction: CGFloat, width: CGFloat = 46, height: CGFloat = 4) -> some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.primary)
                    .frame(width: width * min(max(fraction, 0), 1))
            }
            .animation(.easeOut(duration: 0.1), value: fraction)
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
            || (settings.islandDownloadProgress && model.downloads.activeCount > 0)
            || model.isLowBattery
    }

    // MARK: - Expanded card

    private var expandedContent: some View {
        VStack(spacing: 8) {
            topBar
            switch model.tab {
            case .home: homeRow
            case .shelf: shelfGrid
            case .bluetooth: bluetoothList
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // The little tab row on top: Home / Shelf / Bluetooth on the left (Shelf is
    // a drop target), battery + charge state on the right.
    private var topBar: some View {
        HStack(spacing: 8) {
            tabButton(.home, icon: "house.fill")
            if settings.islandFileShelf {
                tabButton(.shelf, icon: "tray.fill")
                    .overlay(alignment: .topTrailing) {
                        if !model.shelf.items.isEmpty {
                            Text("\(model.shelf.items.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 13, height: 13)
                                .background(.white, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        model.shelf.add(urls: urls)
                        model.tab = .shelf
                        return true
                    }
            }
            tabButton(.bluetooth, icon: "dot.radiowaves.left.and.right")
            Spacer()
            batteryStatus
        }
        .frame(height: 24)
    }

    private func tabButton(_ tab: DynamicIslandModel.Tab, icon: String) -> some View {
        let selected = model.tab == tab
        return Button {
            model.tab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(selected ? 0.14 : 0.04))
                )
        }
        .buttonStyle(.plain)
    }

    private var batteryStatus: some View {
        HStack(spacing: 6) {
            if model.monitor.hasBattery {
                Text("\(Int((model.monitor.batteryLevel * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: BatteryModule.symbol(model.monitor))
                    .font(.system(size: 13))
                    .foregroundStyle(model.sensors.isCharging ? .green : .secondary)
            }
        }
    }

    // MARK: - Home tab: media (+ calendar)

    private var homeRow: some View {
        HStack(spacing: 14) {
            mediaColumn
                .frame(maxWidth: .infinity)
            if settings.islandShowCalendar {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)
                calendarColumn
                    .frame(width: 250)
            }
        }
    }

    private var mediaColumn: some View {
        HStack(spacing: 14) {
            artwork(size: 64, radius: 13)
                // The album color seeps into the island around the cover.
                .background {
                    if player.track != nil {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(albumColor)
                            .blur(radius: 26)
                            .opacity(0.75)
                            .scaleEffect(1.35)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let badge = player.sourceBadge() {
                        Image(nsImage: badge)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .offset(x: 5, y: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(player.track?.title ?? "Nothing playing")
                    .font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(player.track?.artist ?? "Play something to see it here")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                if settings.islandShowSeekBar {
                    SeekBar(
                        progress: player.track?.progress ?? 0,
                        duration: player.track?.duration ?? 0,
                        tint: albumColor,
                        onSeek: { player.seek(to: $0) }
                    )
                    .frame(height: 12)
                    .disabled(player.track == nil)
                    .padding(.top, 2)
                }
                controls
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Calendar column

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            weekStrip
            eventsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        // Scrolling to page through days is handled at the window level (see
        // IslandContainerView); a click opens the Calendar app.
        .onTapGesture { model.calendar.openCalendarApp() }
    }

    private var weekStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(monthLabel)
                .font(.system(size: 16, weight: .bold))
                .fixedSize()
                .padding(.trailing, 6)
                .contentTransition(.numericText())
            // The seven day cells slide together as one unit when paging.
            daysRow
                .id(model.calendar.focusedDate)
                .transition(.asymmetric(
                    insertion: .move(edge: model.calendar.lastShiftForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: model.calendar.lastShiftForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var daysRow: some View {
        let today = Calendar.current.startOfDay(for: nowDate)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(model.calendar.weekDays, id: \.self) { day in
                let isToday = Calendar.current.isDate(day, inSameDayAs: today)
                let isFocused = Calendar.current.isDate(day, inSameDayAs: model.calendar.focusedDate)
                VStack(spacing: 3) {
                    Text(weekdayLabel(day))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.system(size: 12, weight: (isFocused || isToday) ? .bold : .regular))
                        .foregroundStyle(isFocused ? AnyShapeStyle(.white) : (isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)))
                        .frame(width: 22, height: 22)
                        .background {
                            if isFocused { Circle().fill(.tint) }
                            else if isToday { Circle().strokeBorder(.tint, lineWidth: 1) }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var eventsList: some View {
        if model.calendar.access == .denied {
            calendarHint("Allow calendar access", system: "calendar.badge.exclamationmark") {
                model.calendar.requestAccessAgain()
            }
        } else {
            // When there are no events, show nothing at all (just the week strip).
            let events = model.calendar.todaysEvents
            let shown = events.prefix(3)
            let extra = events.count - shown.count
            VStack(alignment: .leading, spacing: 5) {
                ForEach(shown) { event in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: event.calendarColor))
                            .frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if extra > 0 {
                    Text("+\(extra) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func calendarHint(_ text: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12))
                Text(text).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bluetooth tab

    private var bluetoothList: some View {
        Group {
            if !model.bluetooth.isPowered {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("Bluetooth is off").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.bluetooth.devices.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("No paired devices").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.bluetooth.devices) { device in
                            bluetoothRow(device)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bluetoothRow(_ device: BluetoothService.Device) -> some View {
        HStack(spacing: 10) {
            Image(systemName: BluetoothService.symbol(forMajorClass: device.majorClass))
                .font(.system(size: 14))
                .foregroundStyle(device.connected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(device.connected ? "Connected" : "Not connected")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if model.bluetooth.isBusy(device) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 74, alignment: .trailing)
            } else {
                Button(device.connected ? "Disconnect" : "Connect") {
                    model.bluetooth.toggle(device)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(device.connected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var nowDate: Date { Date() }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM"
        return f.string(from: model.calendar.focusedDate)
    }

    private func weekdayLabel(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: day)
    }

    // MARK: - Shelf tab

    private var shelfGrid: some View {
        Group {
            if model.shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("Drop files here to keep them handy")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 8)], spacing: 8) {
                        ForEach(model.shelf.items) { item in
                            fileChip(item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileChip(_ item: FileShelf.Item) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: model.shelf.icon(for: item))
                .resizable().frame(width: 20, height: 20)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.shelf.remove(item) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        HStack(spacing: 22) {
            controlButton("backward.fill", size: 14, enabled: player.track != nil) { player.previousTrack() }
            // Play/pause is always enabled: with nothing playing it opens Spotify.
            controlButton((player.track?.isPlaying ?? false) ? "pause.fill" : "play.fill", size: 17, enabled: true) { player.playPause() }
            controlButton("forward.fill", size: 14, enabled: player.track != nil) { player.nextTrack() }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }

    // MARK: - Visualizer

    /// Little animated equalizer bars for the pod — smooth, deterministic
    /// sine-driven motion (no audio tap needed), tinted from the album art.
    private struct VisualizerBars: View {
        var color: Color = .secondary
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.5) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(color)
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
                if let data = player.track?.artworkData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else if let url = player.track?.artworkURL {
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

    // MARK: - Artwork glow color

    /// A stable identity for the current artwork so the glow recomputes on change.
    private var artworkIdentity: String {
        if let url = player.track?.artworkURL { return url.absoluteString }
        if let data = player.track?.artworkData { return "\(data.count)-\(player.track?.title ?? "")" }
        return "none"
    }

    /// Averages the artwork (remote URL or inline data) to one tint for the glow.
    private static func averageColor(url: URL?, data: Data?) async -> Color? {
        let imageData: Data?
        if let data {
            imageData = data
        } else if let url, let (fetched, _) = try? await URLSession.shared.data(from: url) {
            imageData = fetched
        } else {
            imageData = nil
        }
        guard let imageData,
              let image = NSImage(data: imageData),
              let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else { return nil }

        guard let tiny = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: tiny)
        source.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()

        guard let averaged = tiny.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return nil }
        // Boost saturation/brightness so the accent is vivid, not muddy.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        averaged.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vivid = NSColor(hue: h,
                            saturation: min(1, s * 1.7),
                            brightness: min(1, max(0.62, b)),
                            alpha: 1)
        return Color(nsColor: vivid)
    }
}
