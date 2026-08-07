import AVKit
import SwiftUI
import UIKit

struct PlayerLayoutActions {
    let dismiss: () -> Void
    let showComments: () -> Void
    let showQueue: () -> Void
    let showSleepTimer: () -> Void
    let showEqualizer: () -> Void
    let showAddToPlaylist: () -> Void
}

struct ImmersivePlayerLayout: View {
    @Environment(PlayerService.self) private var player

    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    @Binding var showLyrics: Bool
    @Binding var sliderValue: Double
    @Binding var isSeeking: Bool
    let actions: PlayerLayoutActions

    private var artworkHeight: CGFloat {
        min(
            max(availableSize.height * 0.64, availableSize.width * 1.18),
            availableSize.height * 0.79
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ImmersiveArtworkHero(
                artwork: player.currentTrack?.artwork,
                width: availableSize.width,
                height: artworkHeight,
                totalHeight: availableSize.height
            )

            VStack(spacing: 0) {
                PlayerHeader(
                    safeAreaInsets: safeAreaInsets,
                    actions: actions,
                    showsMetadata: false,
                    foregroundColor: .white
                )

                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                            showLyrics = true
                        }
                    }
                    .frame(maxHeight: .infinity)

                VStack(spacing: 11) {
                    ImmersiveTrackInfoRow(actions: actions)

                    PlayerProgressSlider(
                        sliderValue: $sliderValue,
                        isSeeking: $isSeeking,
                        foregroundColor: .white,
                        secondaryColor: .white.opacity(0.58)
                    )

                    ImmersivePlayerControlDeck(
                        showLyrics: $showLyrics,
                        actions: actions,
                        foregroundColor: .white
                    )
                    .padding(.top, 2)
                }
                .padding(.horizontal, 22)
            }
            .padding(.bottom, max(safeAreaInsets.bottom, 10) + 18)
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .clipped()
    }
}

private struct ImmersiveTrackInfoRow: View {
    @Environment(PlayerService.self) private var player

    let actions: PlayerLayoutActions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTrack?.title ?? String(localized: "未在播放"))
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(player.currentTrack?.artist ?? "")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PlayerFeedbackButton(
                symbol: "bubble.left.and.bubble.right",
                fontSize: 19,
                hitSize: 40,
                color: .white.opacity(0.86),
                weight: .regular,
                accessibilityLabel: "查看评论",
                action: actions.showComments
            )

            if let track = player.currentTrack {
                AnimatedFavoriteButton(
                    track: track,
                    hitSize: 52,
                    iconSize: 35,
                    inactiveColor: .white.opacity(0.86)
                )
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }
}

struct ArtworkPlayerLayout: View {
    @Environment(PlayerService.self) private var player

    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    @Binding var showLyrics: Bool
    @Binding var sliderValue: Double
    @Binding var isSeeking: Bool
    let actions: PlayerLayoutActions

    private var artworkSide: CGFloat {
        let heightRatio = availableSize.height < 760 ? 0.30 : 0.35
        return max(190, min(availableSize.width - 58, availableSize.height * heightRatio))
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerHeader(
                safeAreaInsets: safeAreaInsets,
                actions: actions,
                showsMetadata: false,
                foregroundColor: .white
            )

            Spacer(minLength: 6)

            AmbientRecordArtwork(artwork: player.currentTrack?.artwork)
                .onTapGesture {
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.82)) {
                        showLyrics = true
                    }
                }
                .frame(width: artworkSide, height: artworkSide)
                .shadow(color: .black.opacity(0.46), radius: 34, y: 18)
                .accessibilityLabel("打开歌词")

            Spacer(minLength: 6)

            VStack(spacing: 11) {
                ImmersiveTrackInfoRow(actions: actions)

                PlayerProgressSlider(
                    sliderValue: $sliderValue,
                    isSeeking: $isSeeking,
                    foregroundColor: .white,
                    secondaryColor: .white.opacity(0.56)
                )

                ImmersivePlayerControlDeck(
                    showLyrics: $showLyrics,
                    actions: actions,
                    foregroundColor: .white
                )
                .padding(.top, 2)
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, max(safeAreaInsets.bottom, 10) + 18)
        .frame(width: availableSize.width, height: availableSize.height)
        .clipped()
    }
}

struct LandscapePlayerLayout: View {
    @Environment(PlayerService.self) private var player

    let availableSize: CGSize
    let safeAreaInsets: EdgeInsets
    @Binding var showLyrics: Bool
    @Binding var sliderValue: Double
    @Binding var isSeeking: Bool
    let actions: PlayerLayoutActions

    var body: some View {
        let horizontalInset: CGFloat = 20
        let columnSpacing = min(28, availableSize.width * 0.035)
        let contentHeight = max(
            availableSize.height - safeAreaInsets.top - safeAreaInsets.bottom - 82,
            0
        )
        let contentWidth = max(
            availableSize.width - safeAreaInsets.leading - safeAreaInsets.trailing - horizontalInset * 2,
            0
        )
        let minimumRightColumn = min(max(contentWidth * 0.42, 300), contentWidth * 0.54)
        let coverSide = max(min(contentHeight, contentWidth - minimumRightColumn - columnSpacing), 0)

        VStack(spacing: 0) {
            PlayerHeader(
                safeAreaInsets: safeAreaInsets,
                actions: actions,
                showsMetadata: false,
                foregroundColor: .white
            )

            HStack(spacing: columnSpacing) {
                DiffuseEdgeArtwork(artwork: player.currentTrack?.artwork)
                    .frame(width: coverSide, height: coverSide)
                    .clipped()
                    .accessibilityLabel("当前歌曲封面")

                VStack(spacing: 6) {
                    PlayerLyricsPanel(
                        primaryColor: .white,
                        secondaryColor: .white.opacity(0.42),
                        timingOffset: 0,
                        fontSize: 19,
                        compact: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    PlayerProgressSlider(
                        sliderValue: $sliderValue,
                        isSeeking: $isSeeking,
                        foregroundColor: .white,
                        secondaryColor: .white.opacity(0.58),
                        compact: true
                    )

                    LandscapeTransportControls(foregroundColor: .white)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.leading, safeAreaInsets.leading + horizontalInset)
            .padding(.trailing, safeAreaInsets.trailing + horizontalInset)
            .padding(.bottom, max(safeAreaInsets.bottom, 12))
        }
        .frame(width: availableSize.width, height: availableSize.height)
        .clipped()
    }
}
