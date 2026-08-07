import SwiftUI
import UIKit

struct RemotePlaylistDetailView: View {
    @Environment(PluginManager.self) private var plugins
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library

    @State private var playlist: RemotePlaylistItem
    @State private var tracks: [MusicItem] = []
    @State private var isLoading = true
    @State private var isEnd = true
    @State private var page = 1
    @State private var errorMessage: String?
    @State private var showAddToPlaylist = false
    let topList: Bool

    init(playlist: RemotePlaylistItem, topList: Bool = false) {
        _playlist = State(initialValue: playlist)
        self.topList = topList
    }

    var body: some View {
        ZStack {
            CollectionAmbientBackground(artwork: playlist.artwork)
            List {
                CollectionHero(
                    artwork: playlist.artwork,
                    title: playlist.title,
                    subtitle: playlist.artist,
                    platform: playlist.platform,
                    kind: topList ? .chart : .playlist,
                    hasTracks: !tracks.isEmpty,
                    allFavorited: allFavorited,
                    shuffle: { player.playShuffled(tracks) },
                    play: { player.playAll(tracks) },
                    favorite: toggleFavoriteAll
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !playlist.description.isEmpty {
                    CollectionStory(text: playlist.description)
                        .listRowInsets(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if isLoading && tracks.isEmpty {
                    HStack { Spacer(); ProgressView("正在读取歌单…"); Spacer() }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 30)
                } else if let errorMessage, tracks.isEmpty {
                    ContentUnavailableView("无法读取歌单", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(Array(tracks.enumerated()), id: \.element.stableID) { index, track in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24)
                                MusicRow(track: track, tracks: tracks, showArtwork: false)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        CollectionTrackHeader()
                    }
                    if !isEnd {
                        Button("载入更多") { Task { await load(page: page + 1) } }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("随机播放", systemImage: "shuffle") { player.playShuffled(tracks) }
                    Button("添加全部到歌单", systemImage: "text.badge.plus") { showAddToPlaylist = true }
                    ShareLink(item: playlist.title, subject: Text("歌单"))
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) { AddTracksToPlaylistView(tracks: tracks) }
        .task { await load(page: 1) }
    }

    private var allFavorited: Bool {
        !tracks.isEmpty && tracks.allSatisfy(library.isFavorite)
    }

    private func toggleFavoriteAll() {
        let shouldFavorite = !allFavorited
        for track in tracks where library.isFavorite(track) != shouldFavorite {
            library.toggleFavorite(track)
        }
    }

    private func load(page targetPage: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            if topList {
                tracks = try await plugins.topListDetails(playlist)
                isEnd = true
            } else {
                let details = try await plugins.playlistDetails(playlist, page: targetPage)
                playlist = details.0
                tracks = targetPage == 1 ? details.1 : tracks + details.1
                isEnd = details.2
                page = targetPage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AlbumDetailView: View {
    @Environment(PluginManager.self) private var plugins
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var album: AlbumItem
    @State private var tracks: [MusicItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(album: AlbumItem) { _album = State(initialValue: album) }

    var body: some View {
        ZStack {
            CollectionAmbientBackground(artwork: album.artwork)
            List {
                CollectionHero(
                    artwork: album.artwork,
                    title: album.title,
                    subtitle: album.artist,
                    platform: album.platform,
                    kind: .album,
                    hasTracks: !tracks.isEmpty,
                    allFavorited: allFavorited,
                    shuffle: { player.playShuffled(tracks) },
                    play: { player.playAll(tracks) },
                    favorite: toggleFavoriteAll
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !album.description.isEmpty {
                    CollectionStory(text: album.description)
                        .listRowInsets(.init(top: 14, leading: 18, bottom: 14, trailing: 18))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if isLoading {
                    HStack { Spacer(); ProgressView("正在读取专辑…"); Spacer() }
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 24)
                } else if let errorMessage, tracks.isEmpty {
                    ContentUnavailableView("无法读取专辑", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(tracks) { track in
                            MusicRow(track: track, tracks: tracks, showArtwork: false)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        CollectionTrackHeader()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("播放全部", systemImage: "play.fill") { player.playAll(tracks) }
                    Button("随机播放", systemImage: "shuffle") { player.playShuffled(tracks) }
                    ShareLink(item: "\(album.title) — \(album.artist)")
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await load() }
    }

    private var allFavorited: Bool {
        !tracks.isEmpty && tracks.allSatisfy(library.isFavorite)
    }

    private func toggleFavoriteAll() {
        let shouldFavorite = !allFavorited
        for track in tracks where library.isFavorite(track) != shouldFavorite {
            library.toggleFavorite(track)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let details = try await plugins.albumDetails(album)
            album = details.0
            tracks = details.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum CollectionKind {
    case playlist
    case album
    case chart

    var title: String {
        switch self {
        case .playlist: String(localized: "歌单")
        case .album: String(localized: "专辑")
        case .chart: String(localized: "榜单")
        }
    }
}

private struct CollectionAmbientBackground: View {
    let artwork: String?
    @State private var dominantColor = Color(red: 0.10, green: 0.11, blue: 0.14)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                dominantColor

                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: "music.note.list")
                    .frame(width: proxy.size.width, height: min(proxy.size.height * 0.68, 650))
                    .blur(radius: 56)
                    .scaleEffect(1.22)
                    .saturation(1.14)
                    .opacity(0.40)
                    .frame(maxHeight: .infinity, alignment: .top)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: dominantColor.opacity(0.58), location: 0.42),
                        .init(color: dominantColor, location: 0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: artwork) {
            let color = await ArtworkImageRepository.shared.dominantColor(
                for: artwork,
                fallback: UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                dominantColor = color
            }
        }
    }
}

private struct CollectionHero: View {
    let artwork: String?
    let title: String
    let subtitle: String
    let platform: String
    let kind: CollectionKind
    let hasTracks: Bool
    let allFavorited: Bool
    let shuffle: () -> Void
    let play: () -> Void
    let favorite: () -> Void
    @State private var dominantColor = Color(red: 0.10, green: 0.11, blue: 0.14)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                dominantColor

                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: kind == .album ? "square.stack.fill" : "music.note.list")
                    .frame(width: proxy.size.width, height: 600)

                RemoteArtwork(urlString: artwork, cornerRadius: 0, symbol: kind == .album ? "square.stack.fill" : "music.note.list")
                    .frame(width: proxy.size.width, height: 600)
                    .blur(radius: 34)
                    .scaleEffect(1.15)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.40),
                                .init(color: .black.opacity(0.34), location: 0.56),
                                .init(color: .black, location: 0.76)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.40),
                        .init(color: dominantColor.opacity(0.34), location: 0.56),
                        .init(color: dominantColor.opacity(0.92), location: 0.78),
                        .init(color: dominantColor, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 13) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)

                    Text(subtitle.isEmpty ? kind.title : subtitle)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(kind.title)
                        if PlatformBrand.assetName(for: platform) != nil {
                            PlatformBrandMark(platform: platform, size: 20)
                        } else if !platform.isEmpty {
                            Text(platform)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)

                    heroActions
                        .disabled(!hasTracks)
                        .opacity(hasTracks ? 1 : 0.48)
                        .padding(.top, 12)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: 600)
            .clipped()
        }
        .frame(height: 600)
        .accessibilityElement(children: .contain)
        .task(id: artwork) {
            let color = await ArtworkImageRepository.shared.dominantColor(
                for: artwork,
                fallback: UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                dominantColor = color
            }
        }
    }

    private var heroActions: some View {
        HStack(spacing: 18) {
            Button(action: shuffle) {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.semibold))
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.14), in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 0.8) }
            .accessibilityLabel("随机播放")

            Button(action: play) {
                Label("播放", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .foregroundStyle(dominantColor)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放全部")

            Button(action: favorite) {
                Image(systemName: allFavorited ? "checkmark" : "plus")
                    .font(.title2.weight(.medium))
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(.plain)
            .background(.white.opacity(0.14), in: Circle())
            .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 0.8) }
            .accessibilityLabel(allFavorited ? "取消收藏全部歌曲" : "收藏全部歌曲")
        }
    }
}

private struct CollectionStory: View {
    let text: String
    @State private var isExpanded = false

    private var canExpand: Bool {
        text.count > 120 || text.components(separatedBy: .newlines).count > 4
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 4)
                .mask(alignment: .top) {
                    if canExpand && !isExpanded {
                        LinearGradient(
                            colors: [.black, .black, .black.opacity(0.26)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Rectangle()
                    }
                }
            if canExpand {
                Button(
                    isExpanded ? String(localized: "收起介绍") : String(localized: "展开介绍")
                ) {
                    withAnimation(.snappy(duration: 0.34)) { isExpanded.toggle() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CollectionTrackHeader: View {
    var body: some View {
        Text("曲目")
            .textCase(nil)
    }
}

struct ArtistDetailView: View {
    @Environment(PluginManager.self) private var plugins
    @State var artist: ArtistItem
    @State private var type: MediaType = .music
    @State private var results: [SearchResultItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()
            List {
                VStack(spacing: 13) {
                    RemoteArtwork(urlString: artist.avatar, cornerRadius: 70, symbol: "person.fill")
                        .frame(width: 140, height: 140)
                    Text(artist.name).font(.title.bold())
                    if !artist.description.isEmpty { Text(artist.description).font(.footnote).foregroundStyle(.secondary).lineLimit(3) }
                    Picker("作品", selection: $type) {
                        Text("歌曲").tag(MediaType.music)
                        Text("专辑").tag(MediaType.album)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if let errorMessage, results.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
                ForEach(results) { result in
                    switch result {
                    case .music(let track): MusicRow(track: track, tracks: musicTracks).listRowBackground(Color.clear)
                    case .album(let album):
                        NavigationLink { AlbumDetailView(album: album) } label: {
                            HStack { RemoteArtwork(urlString: album.artwork).frame(width: 50, height: 50); Text(album.title) }
                        }.listRowBackground(Color.clear)
                    default: EmptyView()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: type) { await load() }
    }

    private var musicTracks: [MusicItem] {
        results.compactMap { if case .music(let track) = $0 { track } else { nil } }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do { results = try await plugins.artistWorks(artist, type: type) }
        catch { results = []; errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct AddTracksToPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    let tracks: [MusicItem]
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("现有歌单") {
                    ForEach(library.playlists) { playlist in
                        Button {
                            library.add(tracks, to: playlist)
                            dismiss()
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                }
                Section("新建歌单") {
                    TextField("歌单名称", text: $newName)
                    Button("新建并添加") {
                        _ = library.createPlaylist(name: newName, tracks: tracks)
                        dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
