import SwiftUI

struct LyricsRoamingPlayerLayout: View {
    @Environment(PlayerService.self) private var player

    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    @Binding var showLyrics: Bool
    @Binding var timingOffset: TimeInterval
    @Binding var fontSize: Double
    @State private var showTimingAdjustment = false

    private var isLandscape: Bool {
        availableSize.width > availableSize.height * 1.15
    }

    var body: some View {
        ZStack {
            RemoteArtwork(
                urlString: player.currentTrack?.artwork,
                cornerRadius: 0,
                symbol: "music.note"
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .blur(radius: 18)
            .scaleEffect(1.08)
            .overlay(Color.black.opacity(0.52))

            LinearGradient(
                colors: [.black.opacity(0.12), .black.opacity(0.44), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: returnToArtwork)

            VStack(spacing: 0) {
                PlayerDismissIndicator()
                    .padding(.top, safeAreaInsets.top + 7)
                    .padding(.bottom, isLandscape ? 0 : 5)

                if !isLandscape {
                    Color.clear
                        .frame(height: 8)
                        .accessibilityHidden(true)
                }

                PlayerLyricsPanel(
                    primaryColor: .white,
                    secondaryColor: .white.opacity(0.46),
                    timingOffset: timingOffset,
                    fontSize: fontSize,
                    centered: isLandscape,
                    onBlankTap: returnToArtwork
                )
                .frame(maxWidth: isLandscape ? min(availableSize.width * 0.72, 760) : .infinity, maxHeight: .infinity)
                .padding(.horizontal, isLandscape ? 30 : 22)

                if isLandscape {
                    landscapePlaybackButton
                        .padding(.top, 8)
                        .padding(.bottom, max(safeAreaInsets.bottom, 12))
                } else {
                    portraitPlayerControls
                        .padding(.top, 8)
                        .padding(.horizontal, safeAreaInsets.leading + 18)
                        .padding(.bottom, max(safeAreaInsets.bottom, 12))
                }
            }
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .clipped()
    }

    private var portraitPlayerControls: some View {
        HStack(spacing: 10) {
            RemoteArtwork(
                urlString: player.currentTrack?.artwork,
                cornerRadius: 22,
                symbol: "music.note"
            )
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(.white.opacity(0.16), lineWidth: 0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? String(localized: "未在播放"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(player.currentTrack?.artist ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            playbackButton(size: 48, symbolSize: 22)

            Button {
                showTimingAdjustment.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(.rect)
            }
            .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.84))
            .accessibilityLabel("调节歌词进度")
            .popover(isPresented: $showTimingAdjustment, arrowEdge: .bottom) {
                LyricTimingAdjustmentView(offset: $timingOffset, fontSize: $fontSize)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .frame(maxWidth: min(availableSize.width - 36, 520))
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var landscapePlaybackButton: some View {
        playbackButton(size: 66, symbolSize: 31)
    }

    private func playbackButton(size: CGFloat, symbolSize: CGFloat) -> some View {
        Button {
            player.togglePlayback()
        } label: {
            Group {
                if player.isLoading {
                    ProgressView()
                        .controlSize(size > 50 ? .large : .regular)
                        .tint(.white)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: symbolSize, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .contentShape(.rect)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.88))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.72), trigger: player.isPlaying)
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
    }

    private func returnToArtwork() {
        withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
            showLyrics = false
        }
    }
}

struct PlayerLyricsPanel: View {
    @Environment(PlayerService.self) private var player

    let primaryColor: Color
    let secondaryColor: Color
    let timingOffset: TimeInterval
    let fontSize: Double
    var compact = false
    var centered = false
    var onBlankTap: (() -> Void)?
    @State private var lyricLineFrames: [CGRect] = []

    private let coordinateSpaceName = "player-lyrics-panel"

    private var adjustedProgress: TimeInterval {
        max(0, player.progress + timingOffset)
    }

    private var activeLyricIndex: Int? {
        player.lyrics.lastIndex { $0.time <= adjustedProgress }
    }

    var body: some View {
        Group {
            if player.lyrics.isEmpty {
                Text("暂无歌词")
                    .font(compact ? .title3.bold() : .title2.bold())
                    .foregroundStyle(primaryColor.opacity(0.84))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { onBlankTap?() }
                    .accessibilityLabel("暂无歌词")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: centered ? .center : .leading, spacing: compact ? 11 : 17) {
                            Color.clear
                                .frame(height: compact ? 24 : 80)
                                .contentShape(.rect)
                                .onTapGesture { onBlankTap?() }
                            ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { index, line in
                                let activeIndex = activeLyricIndex ?? 0
                                let distance = abs(index - activeIndex)
                                let isActive = index == activeLyricIndex
                                let nextTime = index + 1 < player.lyrics.count ? player.lyrics[index + 1].time : max(player.duration, line.time + 4)
                                let lineDuration = max(nextTime - line.time, 0.8)
                                let progress = min(max((adjustedProgress - line.time) / lineDuration, 0), 1)

                                Button {
                                    player.seek(to: line.time - timingOffset)
                                } label: {
                                    AnimatedLyricLine(
                                        line: line,
                                        isActive: isActive,
                                        progress: progress,
                                        lineDuration: lineDuration,
                                        isPlaying: player.isPlaying,
                                        fontSize: fontSize,
                                        primaryColor: primaryColor,
                                        secondaryColor: secondaryColor,
                                        centered: centered
                                    )
                                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                                    .scaleEffect(isActive ? 1 : max(0.92, 0.98 - Double(distance) * 0.01), anchor: centered ? .center : .leading)
                                    .opacity(isActive ? 1 : max(0.28, 0.78 - Double(distance) * 0.08))
                                    .blur(radius: isActive ? 0 : min(CGFloat(distance) * 0.38, 2.2))
                                }
                                .buttonStyle(.plain)
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: LyricLineFramesPreferenceKey.self,
                                            value: [geometry.frame(in: .named(coordinateSpaceName))]
                                        )
                                    }
                                }
                                .id(index)
                                .animation(
                                    .spring(response: 0.66, dampingFraction: 0.72, blendDuration: 0.16),
                                    value: activeLyricIndex
                                )
                            }
                            Color.clear
                                .frame(height: compact ? 34 : 90)
                                .contentShape(.rect)
                                .onTapGesture { onBlankTap?() }
                        }
                        .padding(.horizontal, compact ? 4 : 8)
                    }
                    .scrollIndicators(.hidden)
                    .coordinateSpace(name: coordinateSpaceName)
                    .onPreferenceChange(LyricLineFramesPreferenceKey.self) { frames in
                        lyricLineFrames = frames
                    }
                    .simultaneousGesture(
                        SpatialTapGesture(coordinateSpace: .named(coordinateSpaceName))
                            .onEnded { value in
                                let hitPadding: CGFloat = 6
                                let tappedLyric = lyricLineFrames.contains {
                                    $0.insetBy(dx: -hitPadding, dy: -hitPadding).contains(value.location)
                                }
                                if !tappedLyric { onBlankTap?() }
                            }
                    )
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.12),
                                .init(color: .black, location: 0.86),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: activeLyricIndex) { _, index in
                        guard let index else { return }
                        withAnimation(.spring(response: 0.72, dampingFraction: 0.78, blendDuration: 0.18)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct LyricLineFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct AnimatedLyricLine: View {
    let line: TimedLyricLine
    let isActive: Bool
    let progress: Double
    let lineDuration: TimeInterval
    let isPlaying: Bool
    let fontSize: Double
    let primaryColor: Color
    let secondaryColor: Color
    let centered: Bool

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            if centered {
                ZStack {
                    Text(line.text.isEmpty ? "•••" : line.text)
                        .foregroundStyle(isActive ? primaryColor.opacity(0.34) : secondaryColor)
                    if isActive {
                        Text(line.text.isEmpty ? "•••" : line.text)
                            .foregroundStyle(primaryColor)
                            .textRenderer(KaraokeGlyphRenderer(progress: progress))
                    }
                }
                .font(.system(size: isActive ? fontSize : max(15, fontSize - 3), weight: isActive ? .bold : .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .shadow(color: isActive ? primaryColor.opacity(0.20) : .clear, radius: 16)
            } else {
                MarqueeLyricText(
                    text: line.text.isEmpty ? "•••" : line.text,
                    fontSize: CGFloat(isActive ? fontSize : max(15, fontSize - 3)),
                    weight: isActive ? .bold : .semibold,
                    color: isActive ? primaryColor : secondaryColor,
                    progress: isActive ? progress : 0,
                    lineDuration: lineDuration,
                    isPlaying: isPlaying,
                    isActive: isActive
                )
                .shadow(color: isActive ? primaryColor.opacity(0.20) : .clear, radius: 16)
            }

            if let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: max(12, fontSize * 0.58), weight: .regular))
                    .foregroundStyle(isActive ? primaryColor.opacity(0.66) : secondaryColor.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }
        }
    }
}

private struct MarqueeLyricText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let color: Color
    let progress: Double
    let lineDuration: TimeInterval
    let isPlaying: Bool
    let isActive: Bool

    @State private var textWidth: CGFloat = 0
    @State private var progressAnchor = 0.0
    @State private var progressAnchorDate = Date.now

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive || !isPlaying)) { timeline in
                let smoothProgress = interpolatedProgress(at: timeline.date)
                let overflow = max(textWidth - proxy.size.width, 0)
                let marqueePosition = horizontalTravelPosition(for: smoothProgress)

                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Text(text)
                            .font(.system(size: fontSize, weight: weight))
                            .foregroundStyle(isActive ? color.opacity(0.34) : color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        if isActive {
                            Text(text)
                                .font(.system(size: fontSize, weight: weight))
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .textRenderer(KaraokeGlyphRenderer(progress: smoothProgress))
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: -overflow * marqueePosition)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.width
                    } action: { width in
                        textWidth = width
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .mask {
                    if isActive && overflow > 1 {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.025),
                                .init(color: .black, location: 0.94),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Rectangle()
                    }
                }
            }
        }
        .frame(height: fontSize * 1.32)
        .clipped()
        .accessibilityLabel(text)
        .onAppear { synchronizeProgressAnchor() }
        .onChange(of: progress) { _, _ in synchronizeProgressAnchor() }
        .onChange(of: isActive) { _, _ in synchronizeProgressAnchor() }
        .onChange(of: isPlaying) { _, _ in synchronizeProgressAnchor() }
    }

    private func interpolatedProgress(at date: Date) -> Double {
        guard isActive, isPlaying else { return min(max(progress, 0), 1) }
        let elapsed = max(0, date.timeIntervalSince(progressAnchorDate))
        return min(max(progressAnchor + elapsed / max(lineDuration, 0.8), 0), 1)
    }

    private func horizontalTravelPosition(for progress: Double) -> CGFloat {
        switch progress {
        case ..<0.08:
            return 0
        case 0.08..<0.52:
            return CGFloat((progress - 0.08) / 0.44)
        case 0.52..<0.66:
            return 1
        default:
            return CGFloat(max(0, 1 - (progress - 0.66) / 0.34))
        }
    }

    private func synchronizeProgressAnchor() {
        let now = Date.now
        let incoming = min(max(progress, 0), 1)
        let estimated = interpolatedProgress(at: now)
        progressAnchor = abs(incoming - estimated) < 0.08 ? max(incoming, estimated) : incoming
        progressAnchorDate = now
    }
}

private struct KaraokeGlyphRenderer: TextRenderer {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var glyphs: [Text.Layout.RunSlice] = []
        for line in layout {
            for run in line {
                for glyph in run {
                    glyphs.append(glyph)
                }
            }
        }

        guard !glyphs.isEmpty else { return }
        let revealedGlyphs = min(max(progress, 0), 1) * Double(glyphs.count)

        for (index, glyph) in glyphs.enumerated() {
            let visibility = min(max(revealedGlyphs - Double(index), 0), 1)
            guard visibility > 0 else { break }
            var glyphContext = context
            glyphContext.opacity = visibility
            glyphContext.draw(glyph, options: .disablesSubpixelQuantization)
        }
    }
}

private struct LyricTimingAdjustmentView: View {
    @Binding var offset: TimeInterval
    @Binding var fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("歌词进度")
                        .font(.headline)
                    Text(offsetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重置") {
                    offset = 0
                    fontSize = 24
                }
                    .font(.caption.weight(.semibold))
                    .disabled(abs(offset) < 0.05 && abs(fontSize - 24) < 0.5)
            }

            Slider(value: $offset, in: -5...5, step: 0.1)

            HStack {
                Button { offset = max(-5, offset - 0.5) } label: {
                    Label("延后 0.5 秒", systemImage: "minus")
                }
                Spacer()
                Button { offset = min(5, offset + 0.5) } label: {
                    Label("提前 0.5 秒", systemImage: "plus")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)

            Text("歌词比人声慢时向“提前”调节；比人声快时向“延后”调节。")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            HStack {
                Label("歌词字号", systemImage: "textformat.size")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(fontSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $fontSize, in: 18...34, step: 1)
                .accessibilityLabel("歌词字号")
                .accessibilityValue(
                    String(format: String(localized: "%d 点"), Int(fontSize))
                )
        }
        .padding(18)
        .frame(width: 330)
    }

    private var offsetDescription: String {
        if abs(offset) < 0.05 { return String(localized: "当前与播放进度同步") }
        let direction = offset > 0 ? String(localized: "提前") : String(localized: "延后")
        return String(
            format: String(localized: "歌词已%@ %.1f 秒"),
            direction,
            abs(offset)
        )
    }
}
