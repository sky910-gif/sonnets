import SwiftUI
import UIKit

private enum NowPlayingSheetDestination: Identifiable {
    case queue
    case sleepTimer
    case equalizer
    case comments(MusicItem)
    case addToPlaylist(MusicItem)

    var id: String {
        switch self {
        case .queue: "queue"
        case .sleepTimer: "sleep-timer"
        case .equalizer: "equalizer"
        case .comments(let track): "comments-\(track.stableID)"
        case .addToPlaylist(let track): "add-to-playlist-\(track.stableID)"
        }
    }
}

struct NowPlayingView: View {
    @Environment(PlayerService.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var presentedSheet: NowPlayingSheetDestination?
    @State private var sliderValue: Double = 0
    @State private var isSeeking = false
    @State private var lyricTimingOffset: TimeInterval = 0
    @AppStorage("lyricsFontSize") private var lyricFontSize = 24.0
    @State private var previousIdleTimerDisabled = false
    @State private var dismissalTranslation: CGFloat = 0
    @State private var isCompletingInteractiveDismissal = false
    @State private var dismissalFeedback = false

    var body: some View {
        GeometryReader { proxy in
            interactivePlayerContent(in: proxy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: showLyrics)
        .preferredColorScheme(preferredPlayerColorScheme)
        .statusBarHidden(shouldHideStatusBar)
        .presentationBackground(.clear)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.82), trigger: dismissalFeedback)
        .sheet(item: $presentedSheet) { destination in
            sheetContent(for: destination)
        }
        .onChange(of: player.progress) { _, newValue in
            if !isSeeking { sliderValue = newValue }
        }
        .onChange(of: player.currentTrack?.stableID) { _, _ in
            sliderValue = 0
            lyricTimingOffset = 0
        }
        .onAppear {
            keepScreenAwake()
            sliderValue = player.progress
        }
        .onDisappear(perform: handleDisappear)
    }

    private func interactivePlayerContent(in proxy: GeometryProxy) -> some View {
        let size = proxy.size
        let safeAreaInsets = resolvedSafeAreaInsets(proxy.safeAreaInsets)
        let dismissalDistance = max(size.height * 0.72, 1)
        let progress = min(max(dismissalTranslation / dismissalDistance, 0), 1)
        let targetWidth = max(size.width - 32, 1)
        let targetHeight: CGFloat = 62
        let targetCenterY = size.height - max(safeAreaInsets.bottom, 10) - 82
        let targetOffsetY = targetCenterY - size.height * 0.5
        let maskWidth = size.width + (targetWidth - size.width) * progress
        let maskHeight = size.height + (targetHeight - size.height) * progress
        let miniPlayerProgress = min(max((progress - 0.58) / 0.42, 0), 1)

        return ZStack {
            fullPlayerContent(size: size, safeAreaInsets: safeAreaInsets)
                .scaleEffect(1 - progress * 0.055)
                .offset(y: progress * 16)
                .mask {
                    RoundedRectangle(cornerRadius: progress * 31, style: .continuous)
                        .frame(width: maskWidth, height: maskHeight)
                        .offset(y: targetOffsetY * progress)
                }
                .shadow(
                    color: .black.opacity(0.34 * progress),
                    radius: 28 * progress,
                    y: 14 * progress
                )

            MiniPlayer(onOpen: {})
                .frame(width: targetWidth)
                .position(x: size.width * 0.5, y: targetCenterY)
                .scaleEffect(0.94 + miniPlayerProgress * 0.06)
                .opacity(miniPlayerProgress)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(.rect)
        .simultaneousGesture(interactiveDismissGesture(size: size))
    }

    private func interactiveDismissGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !isCompletingInteractiveDismissal,
                      presentedSheet == nil,
                      !isSeeking,
                      (!showLyrics || value.startLocation.y < 180) else { return }

                let vertical = value.translation.height
                guard vertical > 0, vertical > abs(value.translation.width) * 1.08 else { return }
                dismissalTranslation = min(vertical, size.height * 0.72)
            }
            .onEnded { value in
                guard !isCompletingInteractiveDismissal else { return }
                let projected = value.predictedEndTranslation.height
                let shouldDismiss = dismissalTranslation > size.height * 0.20
                    || projected > size.height * 0.32

                guard shouldDismiss else {
                    withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                        dismissalTranslation = 0
                    }
                    return
                }

                isCompletingInteractiveDismissal = true
                dismissalFeedback.toggle()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.90)) {
                    dismissalTranslation = size.height * 0.72
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dismiss()
                    }
                }
            }
    }

    private var layoutActions: PlayerLayoutActions {
        PlayerLayoutActions(
            dismiss: { dismiss() },
            showComments: { presentCurrentTrackSheet { .comments($0) } },
            showQueue: { presentedSheet = .queue },
            showSleepTimer: { presentedSheet = .sleepTimer },
            showEqualizer: { presentedSheet = .equalizer },
            showAddToPlaylist: { presentCurrentTrackSheet { .addToPlaylist($0) } }
        )
    }

    private var preferredPlayerColorScheme: ColorScheme? {
        .dark
    }

    private var shouldHideStatusBar: Bool {
        showLyrics || settings.nowPlayingStyle == .immersive
    }

    @ViewBuilder
    private func fullPlayerContent(size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        let landscape = size.width > size.height * 1.15

        ZStack {
            if settings.nowPlayingStyle == .immersive, !landscape, !showLyrics {
                Color.black
            } else {
                PlayerAmbientBackground(
                    artwork: player.currentTrack?.artwork,
                    dark: true
                )
            }

            if showLyrics {
                LyricsRoamingPlayerLayout(
                    availableSize: size,
                    safeAreaInsets: safeAreaInsets,
                    showLyrics: $showLyrics,
                    timingOffset: $lyricTimingOffset,
                    fontSize: $lyricFontSize
                )
                .transition(.opacity.combined(with: .scale(scale: 1.025)))
            } else if landscape {
                LandscapePlayerLayout(
                    availableSize: size,
                    safeAreaInsets: safeAreaInsets,
                    showLyrics: $showLyrics,
                    sliderValue: $sliderValue,
                    isSeeking: $isSeeking,
                    actions: layoutActions
                )
            } else if settings.nowPlayingStyle == .immersive {
                ImmersivePlayerLayout(
                    availableSize: size,
                    safeAreaInsets: safeAreaInsets,
                    showLyrics: $showLyrics,
                    sliderValue: $sliderValue,
                    isSeeking: $isSeeking,
                    actions: layoutActions
                )
            } else {
                ArtworkPlayerLayout(
                    availableSize: size,
                    safeAreaInsets: safeAreaInsets,
                    showLyrics: $showLyrics,
                    sliderValue: $sliderValue,
                    isSeeking: $isSeeking,
                    actions: layoutActions
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func sheetContent(for destination: NowPlayingSheetDestination) -> some View {
        switch destination {
        case .queue:
            NavigationStack {
                QueueView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { presentedSheet = nil }
                        }
                    }
            }
        case .sleepTimer:
            SleepTimerSheet(isPresented: sheetIsPresentedBinding)
        case .equalizer:
            EqualizerView()
        case .comments(let track):
            CommentsView(track: track)
        case .addToPlaylist(let track):
            AddTracksToPlaylistView(tracks: [track])
        }
    }

    private var sheetIsPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedSheet != nil },
            set: { if !$0 { presentedSheet = nil } }
        )
    }

    private func presentCurrentTrackSheet(
        _ destination: (MusicItem) -> NowPlayingSheetDestination
    ) {
        guard let track = player.currentTrack else { return }
        presentedSheet = destination(track)
    }

    private func keepScreenAwake() {
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func restoreIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    private func handleDisappear() {
        restoreIdleTimer()
    }

    private func resolvedSafeAreaInsets(_ geometryInsets: EdgeInsets) -> EdgeInsets {
        if geometryInsets.top > 0 || geometryInsets.bottom > 0 {
            return geometryInsets
        }
        let uiInsets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(
            top: uiInsets.top,
            leading: uiInsets.left,
            bottom: uiInsets.bottom,
            trailing: uiInsets.right
        )
    }
}

private struct SleepTimerSheet: View {
    @Environment(PlayerService.self) private var player
    @Binding var isPresented: Bool
    @State private var selectedMinutes = 30

    private let minuteOptions = Array(stride(from: 5, through: 180, by: 5))

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("将在 \(timerLabel(selectedMinutes)) 后停止播放")
                    .font(.headline)
                    .padding(.top, 8)

                Picker("定时分钟数", selection: $selectedMinutes) {
                    ForEach(minuteOptions, id: \.self) { minutes in
                        Text(timerLabel(minutes))
                            .font(.title3.monospacedDigit())
                            .tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 148)
                .sensoryFeedback(.selection, trigger: selectedMinutes)

                Button {
                    setTimer(selectedMinutes)
                } label: {
                    Text("开始计时")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if player.sleepTimerEnd != nil {
                    Button("关闭当前定时", role: .destructive) {
                        setTimer(nil)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .navigationTitle("定时关闭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { restoreCurrentTimerSelection() }
    }

    private func setTimer(_ minutes: Int?) {
        player.setSleepTimer(minutes: minutes)
        isPresented = false
    }

    private func restoreCurrentTimerSelection() {
        guard let end = player.sleepTimerEnd else { return }
        let remaining = max(5, Int(ceil(end.timeIntervalSinceNow / 60)))
        let rounded = Int((Double(remaining) / 5).rounded()) * 5
        selectedMinutes = min(max(rounded, 5), 180)
    }

    private func timerLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return String(format: String(localized: "%d 分钟"), minutes)
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0
            ? String(format: String(localized: "%d 小时"), hours)
            : String(format: String(localized: "%d 小时 %d 分钟"), hours, remaining)
    }
}
