import SwiftUI
import UIKit

struct PlayerAmbientBackground: View {
    let artwork: String?
    let dark: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(dark ? .black : .systemBackground)
                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: dark ? 88 : 92)
                    .scaleEffect(1.42)
                    .saturation(1.24)
                    .contrast(1.06)
                    .opacity(dark ? 0.88 : 0.64)

                LinearGradient(
                    colors: dark
                        ? [Color.black.opacity(0.12), Color.black.opacity(0.54)]
                        : [Color(.systemBackground).opacity(0.10), Color(.systemBackground).opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

struct AmbientRecordArtwork: View {
    @Environment(PlayerService.self) private var player
    let artwork: String?
    @State private var accumulatedRotation = 0.0
    @State private var rotationStartDate = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying)) { timeline in
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.black, .white.opacity(0.16), .black, .white.opacity(0.08), .black],
                            center: .center
                        )
                    )
                ForEach(0..<9, id: \.self) { index in
                    Circle()
                        .stroke(.white.opacity(index.isMultiple(of: 2) ? 0.055 : 0.025), lineWidth: 0.8)
                        .padding(CGFloat(index) * 8 + 10)
                }
                RemoteArtwork(urlString: artwork, cornerRadius: 999, symbol: "music.note")
                    .padding(44)
                    .overlay {
                        Circle()
                            .fill(.black.opacity(0.76))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .clear, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
                    .padding(2)
            }
            .rotationEffect(.degrees(rotation(at: timeline.date)))
        }
        .clipShape(Circle())
        .onAppear { rotationStartDate = .now }
        .onChange(of: player.isPlaying) { wasPlaying, _ in
            synchronizeRotation(wasPlaying: wasPlaying)
        }
        .onChange(of: player.currentTrack?.stableID) { _, _ in
            accumulatedRotation = 0
            rotationStartDate = .now
        }
    }

    private func rotation(at date: Date) -> Double {
        guard player.isPlaying else { return accumulatedRotation }
        return accumulatedRotation + date.timeIntervalSince(rotationStartDate) * 15
    }

    private func synchronizeRotation(wasPlaying: Bool) {
        let now = Date.now
        if wasPlaying {
            accumulatedRotation = (
                accumulatedRotation + now.timeIntervalSince(rotationStartDate) * 15
            ).truncatingRemainder(dividingBy: 360)
        }
        rotationStartDate = now
    }
}

struct DiffuseEdgeArtwork: View {
    let artwork: String?
    @State private var dominantColor = Color(red: 0.08, green: 0.09, blue: 0.12)

    var body: some View {
        GeometryReader { proxy in
            let inset = min(max(proxy.size.width * 0.035, 16), 30)
            let innerWidth = max(proxy.size.width - inset * 2, 0)
            let innerHeight = max(proxy.size.height - inset * 2, 0)
            let outerFeather = max(34, inset * 2.25)

            ZStack {
                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note")
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: outerFeather)
                    .scaleEffect(1.16)
                    .saturation(1.18)
                    .opacity(0.76)
                    .mask {
                        RadialGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.74), location: 0.52),
                                .init(color: .white.opacity(0.20), location: 0.78),
                                .init(color: .clear, location: 1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: max(proxy.size.width, proxy.size.height) * 0.68
                        )
                    }

                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note")
                    .frame(width: innerWidth, height: innerHeight)
                    .mask(SoftArtworkEdge(cornerRadius: inset * 0.78, feather: min(inset * 0.95, 24)))
                    .shadow(color: dominantColor.opacity(0.62), radius: 32, y: 14)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .compositingGroup()
            .clipped()
        }
        .task(id: artwork) {
            let color = await ArtworkImageRepository.shared.dominantColor(
                for: artwork,
                fallback: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.42)) {
                dominantColor = color
            }
        }
    }
}

private struct SoftArtworkEdge: View {
    let cornerRadius: CGFloat
    let feather: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.white)
            .blur(radius: feather)
            .padding(feather * 0.34)
    }
}

struct ImmersiveArtworkHero: View {
    let artwork: String?
    let width: CGFloat
    let height: CGFloat
    let totalHeight: CGFloat
    @State private var dominantColor = Color(red: 0.08, green: 0.09, blue: 0.12)

    var body: some View {
        let fadeExtension = min(132, height * 0.22)
        let visualHeight = height + fadeExtension

        ZStack(alignment: .top) {
            dominantColor

            RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note")
                .frame(width: width, height: visualHeight)
                .blur(radius: 34)
                .scaleEffect(1.13)
                .saturation(1.08)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: .black.opacity(0.24), location: 0.56),
                            .init(color: .black, location: 0.74),
                            .init(color: .black.opacity(0.56), location: 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note")
                .frame(width: width, height: height)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.64),
                            .init(color: .black.opacity(0.90), location: 0.76),
                            .init(color: .black.opacity(0.42), location: 0.90),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.24), location: 0),
                    .init(color: .clear, location: 0.20),
                    .init(color: .clear, location: 0.48),
                    .init(color: dominantColor.opacity(0.16), location: 0.61),
                    .init(color: dominantColor.opacity(0.56), location: 0.75),
                    .init(color: dominantColor.opacity(0.92), location: 0.90),
                    .init(color: dominantColor, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: visualHeight)
        }
        .frame(width: width, height: max(totalHeight, visualHeight), alignment: .top)
        .clipped()
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: artwork) {
            let color = await ArtworkImageRepository.shared.dominantColor(
                for: artwork,
                fallback: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                dominantColor = color
            }
        }
    }
}

struct ImmersiveCommentBarrage: View {
    @Environment(PluginManager.self) private var plugins

    let track: MusicItem?
    let onOpenComments: () -> Void
    @State private var comments: [MusicComment] = []

    private var firstLane: [MusicComment] {
        comments.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
    }

    private var secondLane: [MusicComment] {
        comments.enumerated().compactMap { $0.offset.isMultiple(of: 2) ? nil : $0.element }
    }

    var body: some View {
        Group {
            if !comments.isEmpty {
                VStack(spacing: 6) {
                    CommentBarrageLane(
                        comments: firstLane,
                        automaticInterval: 3.8,
                        onOpenComments: onOpenComments
                    )

                    if !secondLane.isEmpty {
                        CommentBarrageLane(
                            comments: secondLane,
                            automaticInterval: 4.6,
                            onOpenComments: onOpenComments
                        )
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.93),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .task(id: track?.stableID) {
            await loadComments()
        }
    }

    private func loadComments() async {
        comments = []
        guard let track, plugins.supportsComments(for: track) else { return }

        do {
            let page = try await plugins.comments(for: track, page: 1)
            guard !Task.isCancelled else { return }
            let loaded = Array(page.comments.filter { !$0.content.isEmpty }.prefix(24))
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                comments = loaded
            }
        } catch is CancellationError {
            return
        } catch {
            comments = []
        }
    }
}

private struct CommentBarrageLane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let comments: [MusicComment]
    let automaticInterval: Double
    let onOpenComments: () -> Void

    @State private var visibleCommentIndex: Int?
    @State private var pauseAutomaticScrollUntil = Date.distantPast

    private var loopingComments: [MusicComment] {
        guard let first = comments.first, comments.count > 1 else { return comments }
        return comments + [first]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 9) {
                ForEach(Array(loopingComments.enumerated()), id: \.offset) { index, comment in
                    CommentBarrageCapsule(
                        comment: comment,
                        action: onOpenComments
                    )
                    .id(index)
                    .accessibilityHidden(index == comments.count)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 7)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleCommentIndex, anchor: .leading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in pauseAutomaticScroll() }
                .onEnded { _ in pauseAutomaticScroll() }
        )
        .task(id: comments.map(\.id)) {
            visibleCommentIndex = comments.isEmpty ? nil : 0
            await runAutomaticScroll()
        }
        .frame(height: 42)
    }

    private func runAutomaticScroll() async {
        guard comments.count > 1, !reduceMotion else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(automaticInterval))
            } catch {
                return
            }
            guard Date.now >= pauseAutomaticScrollUntil, scenePhase == .active else { continue }

            let currentIndex = min(max(visibleCommentIndex ?? 0, 0), comments.count - 1)
            let nextIndex = currentIndex + 1
            withAnimation(.linear(duration: 0.92)) {
                visibleCommentIndex = nextIndex
            }

            if nextIndex == comments.count {
                do {
                    try await Task.sleep(for: .seconds(1.0))
                } catch {
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    visibleCommentIndex = 0
                }
            }
        }
    }

    private func pauseAutomaticScroll() {
        pauseAutomaticScrollUntil = Date.now.addingTimeInterval(8)
    }
}

private struct CommentBarrageCapsule: View {
    let comment: MusicComment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RemoteArtwork(urlString: comment.avatar, cornerRadius: 15, symbol: "person.fill")
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle().stroke(.white.opacity(0.22), lineWidth: 0.7)
                    }

                Text(comment.content)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(maxWidth: 280, minHeight: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(comment.nickname)：\(comment.content)")
        .accessibilityHint("轻点查看全部评论")
    }
}
