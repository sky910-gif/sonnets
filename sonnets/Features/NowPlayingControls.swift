import AVKit
import SwiftUI
import UIKit

struct PlayerHeader: View {
    let safeAreaInsets: EdgeInsets
    let actions: PlayerLayoutActions
    let showsMetadata: Bool
    let foregroundColor: Color

    var body: some View {
        VStack(spacing: 5) {
            PlayerDismissIndicator()

            PlayerTopControls(
                actions: actions,
                centeredPlatform: showsMetadata,
                foregroundColor: foregroundColor
            )
        }
        .padding(.top, safeAreaInsets.top + 7)
        .padding(.leading, safeAreaInsets.leading + 22)
        .padding(.trailing, safeAreaInsets.trailing + 22)
    }
}

struct PlayerDismissIndicator: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.68))
            .frame(width: 44, height: 5)
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

private struct PlayerTopControls: View {
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PluginManager.self) private var plugins
    @Environment(AppSettings.self) private var settings

    let actions: PlayerLayoutActions
    let centeredPlatform: Bool
    let foregroundColor: Color

    var body: some View {
        HStack {
            Button(action: actions.dismiss) {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
            }
            .playerCircleGlassStyle()

            Spacer()

            if centeredPlatform {
                VStack(spacing: 3) {
                    Text(player.currentTrack?.title ?? String(localized: "未在播放"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(player.currentTrack?.artist ?? "")
                        .font(.caption)
                        .opacity(0.68)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 220)
                .multilineTextAlignment(.center)
            }

            Spacer()

            Menu {
                Section("播放界面") {
                    Picker("播放界面", selection: Binding(
                        get: { settings.nowPlayingStyle },
                        set: { settings.nowPlayingStyle = $0 }
                    )) {
                        ForEach(NowPlayingStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbol).tag(style)
                        }
                    }
                }

                Section("音质") {
                    Picker("音质", selection: Binding(
                        get: { settings.quality },
                        set: { settings.quality = $0 }
                    )) {
                        ForEach(AudioQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                }

                Section("播放速度") {
                    Picker("播放速度", selection: Binding(
                        get: { settings.playbackRate },
                        set: { player.setPlaybackRate($0) }
                    )) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Text("\(rate.formatted(.number.precision(.fractionLength(0...2))))×").tag(rate)
                        }
                    }
                }

                if let track = player.currentTrack {
                    Section("歌曲操作") {
                        Button("添加到歌单", systemImage: "text.badge.plus", action: actions.showAddToPlaylist)

                        if library.activeDownloads.contains(track.stableID) {
                            Label("正在下载…", systemImage: "arrow.down.circle.dotted")
                        } else if !library.isDownloaded(track) {
                            Button("下载", systemImage: "arrow.down.circle") {
                                Task {
                                    await library.download(track, using: plugins, quality: settings.quality)
                                }
                            }
                        }

                        ShareLink(item: "\(track.title) — \(track.artist)") {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 40, height: 40)
            }
            .playerCircleGlassStyle()
            .accessibilityLabel("播放选项")
        }
        .foregroundStyle(foregroundColor)
        .frame(height: 50)
    }

}

struct PlayerProgressSlider: View {
    @Environment(PlayerService.self) private var player

    @Binding var sliderValue: Double
    @Binding var isSeeking: Bool
    let foregroundColor: Color
    let secondaryColor: Color
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            DogProgressTrack(
                value: $sliderValue,
                duration: max(player.duration, 1),
                compact: compact,
                foregroundColor: foregroundColor,
                isSeeking: $isSeeking,
                onSeek: player.seek(to:)
            )

            HStack {
                Text(currentTime.playbackTime)
                Spacer()
                Text("-\(max(player.duration - currentTime, 0).playbackTime)")
            }
            .font((compact ? Font.caption2 : Font.caption).monospacedDigit())
            .foregroundStyle(secondaryColor)
        }
        .padding(.top, compact ? 0 : 9)
    }

    private var currentTime: TimeInterval {
        isSeeking ? sliderValue : player.progress
    }

}

private struct DogProgressTrack: View {
    @Binding var value: Double
    let duration: Double
    let compact: Bool
    let foregroundColor: Color
    @Binding var isSeeking: Bool
    let onSeek: (TimeInterval) -> Void

    private var dogSize: CGFloat { compact ? 27 : 34 }
    private var trackHeight: CGFloat { compact ? 4 : 5 }

    var body: some View {
        GeometryReader { proxy in
            let normalized = min(max(value / duration, 0), 1)
            let usableWidth = max(proxy.size.width - dogSize, 1)
            let dogX = dogSize * 0.5 + usableWidth * normalized

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(foregroundColor.opacity(0.24))
                    .frame(height: trackHeight)
                    .padding(.horizontal, dogSize * 0.5)

                Capsule()
                    .fill(foregroundColor)
                    .frame(width: max(dogX - dogSize * 0.5, 1), height: trackHeight)
                    .offset(x: dogSize * 0.5)

                BundledLottieAnimation(name: "walking_dog-2")
                    .frame(width: dogSize, height: dogSize)
                    .position(x: dogX, y: proxy.size.height * 0.5)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isSeeking = true
                        value = seekValue(at: gesture.location.x, width: proxy.size.width)
                    }
                    .onEnded { gesture in
                        value = seekValue(at: gesture.location.x, width: proxy.size.width)
                        isSeeking = false
                        onSeek(value)
                    }
            )
        }
        .frame(height: dogSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放进度")
        .accessibilityValue(value.playbackTime)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(duration, value + 15)
            case .decrement:
                value = max(0, value - 15)
            @unknown default:
                break
            }
            onSeek(value)
        }
    }

    private func seekValue(at x: CGFloat, width: CGFloat) -> Double {
        let usableWidth = max(width - dogSize, 1)
        let normalized = min(max((x - dogSize * 0.5) / usableWidth, 0), 1)
        return duration * normalized
    }
}

struct PlayerControlDeck: View {
    @Environment(PlayerService.self) private var player

    @Binding var showLyrics: Bool
    let actions: PlayerLayoutActions
    let foregroundColor: Color
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 2 : 8) {
            HStack {
                playbackModeMenu
                Spacer()
                PlayerFeedbackButton(
                    symbol: "backward.fill",
                    fontSize: compact ? 20 : 26,
                    hitSize: compact ? 42 : 52,
                    color: foregroundColor,
                    accessibilityLabel: "上一首",
                    action: player.previous
                )
                .disabled(!player.hasPrevious)
                .opacity(player.hasPrevious ? 1 : 0.38)

                Spacer()
                PlayerPlayButton(
                    foregroundColor: foregroundColor,
                    compact: compact
                )

                Spacer()
                PlayerFeedbackButton(
                    symbol: "forward.fill",
                    fontSize: compact ? 20 : 26,
                    hitSize: compact ? 42 : 52,
                    color: foregroundColor,
                    accessibilityLabel: "下一首",
                    action: player.next
                )
                .disabled(!player.hasNext)
                .opacity(player.hasNext ? 1 : 0.38)

                Spacer()
                PlayerFeedbackButton(
                    symbol: "music.note.list",
                    fontSize: compact ? 19 : 23,
                    hitSize: compact ? 42 : 52,
                    color: foregroundColor,
                    accessibilityLabel: "播放队列",
                    action: actions.showQueue
                )
            }

            HStack {
                Spacer()
                PlayerFeedbackButton(
                    symbol: showLyrics ? "photo" : "text.quote",
                    fontSize: compact ? 17 : 21,
                    hitSize: compact ? 38 : 44,
                    color: foregroundColor.opacity(0.82),
                    weight: .regular,
                    accessibilityLabel: showLyrics ? "返回封面" : "显示歌词"
                ) {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                        showLyrics.toggle()
                    }
                }

                Spacer()
                PlayerFeedbackButton(
                    symbol: "bubble.left.and.bubble.right",
                    fontSize: compact ? 17 : 21,
                    hitSize: compact ? 38 : 44,
                    color: foregroundColor.opacity(0.82),
                    weight: .regular,
                    accessibilityLabel: "查看评论",
                    action: actions.showComments
                )

                Spacer()
                PlayerFeedbackButton(
                    symbol: "timer",
                    fontSize: compact ? 17 : 21,
                    hitSize: compact ? 38 : 44,
                    color: player.sleepTimerEnd == nil ? foregroundColor.opacity(0.82) : Color.accentColor,
                    weight: .regular,
                    accessibilityLabel: player.sleepTimerEnd == nil ? "设置定时关闭" : "修改定时关闭",
                    action: actions.showSleepTimer
                )

                Spacer()
                PlayerFeedbackButton(
                    symbol: "slider.vertical.3",
                    fontSize: compact ? 17 : 20,
                    hitSize: compact ? 38 : 44,
                    color: player.equalizerEnabled ? Color.green : foregroundColor.opacity(0.82),
                    weight: .regular,
                    accessibilityLabel: player.equalizerEnabled ? "均衡器，已开启" : "均衡器，已关闭",
                    action: actions.showEqualizer
                )

                Spacer()
                favoriteButton

                Spacer()
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.001))
                    SystemRoutePicker(tint: .white)
                        .padding(compact ? 8 : 10)
                }
                .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
                .accessibilityLabel("选择播放设备")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases) { mode in
                Button {
                    player.setPlaybackMode(mode)
                } label: {
                    Label(mode.title, systemImage: player.playbackMode == mode ? "checkmark" : mode.symbol)
                }
            }
        } label: {
            Image(systemName: player.playbackMode.symbol)
                .font(.system(size: compact ? 18 : 22, weight: .semibold))
                .foregroundStyle(player.playbackMode == .sequential ? foregroundColor : Color.accentColor)
                .frame(width: compact ? 42 : 52, height: compact ? 42 : 52)
                .contentShape(.rect)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.84))
        .accessibilityLabel("播放模式：\(player.playbackMode.title)")
    }

    @ViewBuilder
    private var favoriteButton: some View {
        if let track = player.currentTrack {
            AnimatedFavoriteButton(
                track: track,
                hitSize: compact ? 48 : 52,
                iconSize: compact ? 31 : 35,
                inactiveColor: foregroundColor.opacity(0.82)
            )
        }
    }
}

struct AnimatedFavoriteButton: View {
    @Environment(LibraryStore.self) private var library

    let track: MusicItem
    let hitSize: CGFloat
    let iconSize: CGFloat
    let inactiveColor: Color
    @State private var animationTrigger = 0
    @State private var feedbackTrigger = 0
    @State private var displayedFavorite: Bool?

    private var isFavorite: Bool {
        displayedFavorite ?? library.isFavorite(track)
    }

    var body: some View {
        Button(action: toggleFavorite) {
            ZStack {
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: iconSize * 0.82, weight: .semibold))
                        .foregroundStyle(.pink)
                        .symbolEffect(.bounce, value: animationTrigger)
                        .transition(.scale(scale: 0.72).combined(with: .opacity))

                    TriggeredLottieAnimation(name: "pulsing_heart", trigger: animationTrigger)
                        .frame(width: iconSize * 1.14, height: iconSize * 1.14)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "heart")
                        .font(.system(size: iconSize * 0.84, weight: .regular))
                        .foregroundStyle(inactiveColor)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }
            }
            .frame(width: hitSize, height: hitSize)
            .contentShape(.interaction, Circle())
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.82))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.72), trigger: feedbackTrigger)
        .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
        .onAppear {
            displayedFavorite = library.isFavorite(track)
        }
        .onChange(of: track.stableID) { _, _ in
            displayedFavorite = library.isFavorite(track)
        }
        .onChange(of: library.isFavorite(track)) { _, favorite in
            displayedFavorite = favorite
        }
    }

    private func toggleFavorite() {
        let nextFavorite = !isFavorite
        displayedFavorite = nextFavorite
        if nextFavorite { animationTrigger += 1 }
        feedbackTrigger += 1
        library.toggleFavorite(track)
    }
}

/// A lighter, four-action utility row for the immersive cover treatment.
/// Comments and favourites intentionally live next to the track metadata in this layout.
struct ImmersivePlayerControlDeck: View {
    @Environment(PlayerService.self) private var player

    @Binding var showLyrics: Bool
    let actions: PlayerLayoutActions
    let foregroundColor: Color

    var body: some View {
        VStack(spacing: 13) {
            HStack {
                playbackModeMenu
                Spacer()
                PlayerFeedbackButton(
                    symbol: "backward.fill",
                    fontSize: 26,
                    hitSize: 52,
                    color: foregroundColor,
                    accessibilityLabel: "上一首",
                    action: player.previous
                )
                .disabled(!player.hasPrevious)
                .opacity(player.hasPrevious ? 1 : 0.38)

                Spacer()
                PlayerPlayButton(foregroundColor: foregroundColor, compact: false)
                Spacer()

                PlayerFeedbackButton(
                    symbol: "forward.fill",
                    fontSize: 26,
                    hitSize: 52,
                    color: foregroundColor,
                    accessibilityLabel: "下一首",
                    action: player.next
                )
                .disabled(!player.hasNext)
                .opacity(player.hasNext ? 1 : 0.38)

                Spacer()
                PlayerFeedbackButton(
                    symbol: "music.note.list",
                    fontSize: 23,
                    hitSize: 52,
                    color: foregroundColor,
                    accessibilityLabel: "播放队列",
                    action: actions.showQueue
                )
            }

            HStack(spacing: 0) {
                utilityButton(
                    symbol: showLyrics ? "photo" : "text.quote",
                    label: showLyrics ? "返回封面" : "显示歌词"
                ) {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                        showLyrics.toggle()
                    }
                }
                .frame(maxWidth: .infinity)

                utilityButton(
                    symbol: "timer",
                    label: player.sleepTimerEnd == nil ? "设置定时关闭" : "修改定时关闭",
                    color: player.sleepTimerEnd == nil ? foregroundColor : .accentColor,
                    action: actions.showSleepTimer
                )
                .frame(maxWidth: .infinity)

                utilityButton(
                    symbol: "slider.vertical.3",
                    label: player.equalizerEnabled ? "均衡器，已开启" : "均衡器，已关闭",
                    color: player.equalizerEnabled ? .green : foregroundColor,
                    action: actions.showEqualizer
                )
                .frame(maxWidth: .infinity)

                ZStack {
                    Circle().fill(.white.opacity(0.001))
                    SystemRoutePicker(tint: .white)
                        .padding(9)
                }
                .frame(width: 42, height: 42)
                .opacity(0.68)
                .accessibilityLabel("选择播放设备")
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func utilityButton(
        symbol: String,
        label: LocalizedStringKey,
        color: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        PlayerFeedbackButton(
            symbol: symbol,
            fontSize: 20,
            hitSize: 42,
            color: (color ?? foregroundColor).opacity(0.70),
            weight: .regular,
            accessibilityLabel: label,
            action: action
        )
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases) { mode in
                Button {
                    player.setPlaybackMode(mode)
                } label: {
                    Label(mode.title, systemImage: player.playbackMode == mode ? "checkmark" : mode.symbol)
                }
            }
        } label: {
            Image(systemName: player.playbackMode.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(player.playbackMode == .sequential ? foregroundColor : Color.accentColor)
                .frame(width: 52, height: 52)
                .contentShape(.rect)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.84))
        .accessibilityLabel("播放模式：\(player.playbackMode.title)")
    }
}

struct LandscapeTransportControls: View {
    @Environment(PlayerService.self) private var player

    let foregroundColor: Color

    var body: some View {
        HStack {
            Spacer()
            PlayerFeedbackButton(
                symbol: "backward.fill",
                fontSize: 24,
                hitSize: 48,
                color: foregroundColor,
                accessibilityLabel: "上一首",
                action: player.previous
            )
            .disabled(!player.hasPrevious)
            .opacity(player.hasPrevious ? 1 : 0.38)

            Spacer()
            PlayerPlayButton(foregroundColor: foregroundColor, compact: true)

            Spacer()
            PlayerFeedbackButton(
                symbol: "forward.fill",
                fontSize: 24,
                hitSize: 48,
                color: foregroundColor,
                accessibilityLabel: "下一首",
                action: player.next
            )
            .disabled(!player.hasNext)
            .opacity(player.hasNext ? 1 : 0.38)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct PlayerPlayButton: View {
    @Environment(PlayerService.self) private var player

    let foregroundColor: Color
    let compact: Bool
    @State private var feedbackTrigger = 0

    var body: some View {
        Button(action: activate) {
            Group {
                if player.isLoading {
                    ProgressView()
                        .controlSize(compact ? .regular : .large)
                        .tint(foregroundColor)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 28 : 36, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: feedbackTrigger)
                }
            }
            .frame(width: compact ? 52 : 68, height: compact ? 52 : 68)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.88))
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.78), trigger: feedbackTrigger)
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
    }

    private func activate() {
        feedbackTrigger += 1
        player.togglePlayback()
    }
}

struct PlayerFeedbackButton: View {
    let symbol: String
    let fontSize: CGFloat
    let hitSize: CGFloat
    let color: Color
    var weight: Font.Weight = .semibold
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    @State private var feedbackTrigger = 0

    var body: some View {
        Button(action: activate) {
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(color)
                .frame(width: hitSize, height: hitSize)
                .contentShape(.rect)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: feedbackTrigger)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.82))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.68), trigger: feedbackTrigger)
        .accessibilityLabel(accessibilityLabel)
    }

    private func activate() {
        feedbackTrigger += 1
        action()
    }
}

struct PlayerPressFeedbackStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.84

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct SystemRoutePicker: UIViewRepresentable {
    var tint: UIColor = .label

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = tint
        picker.activeTintColor = tint
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tint
        uiView.activeTintColor = tint
    }
}

extension View {
    @ViewBuilder
    func playerCircleGlassStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
