import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor
@Observable
final class HomeDiscoveryStore {
    var topListGroups: [TopListGroup] = []
    var recommendTags: [PlaylistTag] = []
    var selectedRecommendTag: PlaylistTag?
    var recommendedPlaylists: [RemotePlaylistItem] = []
    var isLoadingCharts = false
    var isRefreshingRecommendations = false
    var loadedPluginID: UUID?
    var hasLoaded = false

    func loadDiscovery(using plugins: PluginManager) async {
        let pluginID = plugins.selectedPluginID
        guard loadedPluginID != pluginID || !hasLoaded else { return }
        hasLoaded = true
        loadedPluginID = pluginID
        topListGroups = []
        recommendTags = []
        selectedRecommendTag = nil
        recommendedPlaylists = []
        await loadCharts(using: plugins, pluginID: pluginID)
        guard !Task.isCancelled, loadedPluginID == pluginID else { return }
        await loadRecommendationCatalog(using: plugins, pluginID: pluginID)
    }

    func refreshRecommendations(using plugins: PluginManager) async {
        guard !isRefreshingRecommendations,
              let tag = selectedRecommendTag ?? recommendTags.first else { return }
        isRefreshingRecommendations = true
        defer { isRefreshingRecommendations = false }

        if loadedPluginID != plugins.selectedPluginID {
            await loadDiscovery(using: plugins)
        } else {
            await loadRecommendations(for: tag, using: plugins, pluginID: loadedPluginID)
        }
    }

    private func loadCharts(using plugins: PluginManager, pluginID: UUID?) async {
        guard let id = pluginID,
              plugins.enabledPlugins.first(where: { $0.id == id })?.manifest.supportedMethods.contains("getTopLists") == true else {
            topListGroups = []
            isLoadingCharts = false
            return
        }
        isLoadingCharts = true
        let loaded = (try? await plugins.topLists(using: id)) ?? []
        guard !Task.isCancelled, loadedPluginID == id else { return }
        topListGroups = loaded
        isLoadingCharts = false
    }

    private func loadRecommendationCatalog(using plugins: PluginManager, pluginID: UUID?) async {
        guard let id = pluginID,
              let plugin = plugins.enabledPlugins.first(where: { $0.id == id }),
              plugin.manifest.supportedMethods.contains("getRecommendSheetTags"),
              plugin.manifest.supportedMethods.contains("getRecommendSheetsByTag") else {
            recommendTags = []
            selectedRecommendTag = nil
            recommendedPlaylists = []
            return
        }
        guard let tags = try? await plugins.recommendTags(using: id),
              !Task.isCancelled,
              loadedPluginID == id else { return }
        recommendTags = tags.pinned.isEmpty ? tags.groups.flatMap(\.tags) : tags.pinned
        if let tag = recommendTags.first {
            await loadRecommendations(for: tag, using: plugins, pluginID: id)
        }
    }

    private func loadRecommendations(for tag: PlaylistTag, using plugins: PluginManager, pluginID: UUID?) async {
        guard let id = pluginID else { return }
        selectedRecommendTag = tag
        let loaded = (try? await plugins.recommendPlaylists(using: id, tag: tag)) ?? []
        guard !Task.isCancelled, loadedPluginID == id else { return }
        var seen = Set<String>()
        recommendedPlaylists = loaded.filter { seen.insert($0.stableID).inserted }
    }
}

struct HomeView: View {
    @Environment(PluginManager.self) private var plugins
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player

    let discovery: HomeDiscoveryStore
    @State private var showImportPlaylist = false
    @State private var destination: HomeDestination?

    private let cardSide: CGFloat = 140

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if plugins.plugins.isEmpty || plugins.isWorking { pluginStatus }
                    recentlyPlayed
                    localPlaylists
                    recommendations
                    charts
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Sonnets")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("导入歌单", systemImage: "square.and.arrow.down") {
                        showImportPlaylist = true
                    }
                    Button("下载", systemImage: "arrow.down.circle.fill") {
                        destination = .downloads
                    }
                    Button("播放历史", systemImage: "clock.fill") {
                        destination = .history
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("导入与快捷操作")

                NavigationLink { QueueView() } label: { HomeQueueToolbarIcon() }
                    .accessibilityLabel("播放列表")
            }
        }
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .downloads: DownloadsView()
            case .history: HistoryView()
            }
        }
        .sheet(isPresented: $showImportPlaylist) { ImportPlaylistView() }
    }

    private var pluginStatus: some View {
        GlassSurface(cornerRadius: 24) {
            HStack(spacing: 14) {
                Image(systemName: plugins.isWorking ? "arrow.trianglehead.2.clockwise.rotate.90" : "puzzlepiece.extension.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.rotate, isActive: plugins.isWorking)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plugins.isWorking ? String(localized: "正在准备音乐插件") : String(localized: "需要添加音乐插件"))
                        .font(.headline)
                    Text(plugins.statusMessage.isEmpty ? String(localized: "可在设置中导入网络插件源") : plugins.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !plugins.isWorking {
                    NavigationLink { PluginSettingsView() } label: { Image(systemName: "chevron.right") }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var recentlyPlayed: some View {
        if !library.history.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("最近播放")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    NavigationLink { HistoryView() } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("查看全部最近播放")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 8) {
                        ForEach(library.history.prefix(12)) { entry in
                            Button { player.play(entry.track) } label: {
                                RecentPlayCard(track: entry.track)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 8)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 0)
                .coordinateSpace(name: "recently-played")
            }
        }
    }

    @ViewBuilder
    private var localPlaylists: some View {
        if !library.playlists.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                Text("我的歌单").font(.system(size: 22, weight: .bold, design: .rounded))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(library.playlists.prefix(10)) { playlist in
                            NavigationLink { LocalPlaylistDetailView(playlistID: playlist.id) } label: {
                                HomeMediaCard(
                                    artwork: playlist.artwork ?? playlist.tracks.first?.artwork,
                                    title: playlist.name,
                                    subtitle: String(
                                        format: String(localized: "%d 首"),
                                        playlist.tracks.count
                                    ),
                                    side: cardSide,
                                    symbol: "music.note.list"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recommendations: some View {
        if !discovery.recommendedPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("推荐歌单").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    if !discovery.recommendTags.isEmpty {
                        Button {
                            Task { await discovery.refreshRecommendations(using: plugins) }
                        } label: {
                            Image(systemName: discovery.isRefreshingRecommendations ? "arrow.clockwise" : "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 32, height: 32)
                                .symbolEffect(.rotate, isActive: discovery.isRefreshingRecommendations)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(discovery.isRefreshingRecommendations)
                        .accessibilityLabel("刷新推荐歌单")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(discovery.recommendedPlaylists, id: \.stableID) { playlist in
                            NavigationLink { RemotePlaylistDetailView(playlist: playlist) } label: {
                                HomeMediaCard(
                                    artwork: playlist.artwork,
                                    title: playlist.title,
                                    subtitle: playlist.artist,
                                    side: cardSide,
                                    symbol: "music.note.list",
                                    platform: playlist.platform
                                )
                            }
                            .frame(width: cardSide)
                            .buttonStyle(.plain)
                            .id(playlist.stableID)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var charts: some View {
        if discovery.isLoadingCharts {
            HStack { Spacer(); ProgressView("正在读取榜单…"); Spacer() }.padding(.vertical, 30)
        } else {
            ForEach(discovery.topListGroups) { group in
                VStack(alignment: .leading, spacing: 13) {
                    Text(group.title).font(.system(size: 22, weight: .bold, design: .rounded))
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(group.playlists) { playlist in
                                NavigationLink { RemotePlaylistDetailView(playlist: playlist, topList: true) } label: {
                                    HomeMediaCard(
                                    artwork: playlist.artwork,
                                    title: playlist.title,
                                    subtitle: "",
                                    side: cardSide,
                                    symbol: "chart.line.uptrend.xyaxis",
                                    platform: playlist.platform
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

}

private struct HomeQueueToolbarIcon: View {
    var body: some View {
        Image(systemName: "music.note.list")
            .font(.body.weight(.semibold))
        .frame(width: 24, height: 20)
        .accessibilityHidden(true)
    }
}

private enum HomeDestination: Hashable {
    case downloads
    case history
}

private struct RecentPlayCard: View {
    let track: MusicItem

    private let artworkAspectRatio: CGFloat = 0.76
    private let cornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let cardFrame = proxy.frame(in: .named("recently-played"))
                let horizontalProgress = cardFrame.minX / max(proxy.size.width, 1)
                let artworkOffset = max(-38, min(38, -horizontalProgress * 23))

                RemoteArtwork(urlString: track.artwork, cornerRadius: cornerRadius)
                    .frame(width: proxy.size.width + 76, height: proxy.size.height)
                    .offset(x: artworkOffset - 38)
                    .scaleEffect(1.13)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(0.07), .clear, .black.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: artworkOffset)
            }
            .aspectRatio(artworkAspectRatio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 7, y: 3)

            Text(track.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(track.artist)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放 \(track.title)，\(track.artist)")
    }
}

private struct HomeMediaCard: View {
    let artwork: String?
    let title: String
    let subtitle: String
    let side: CGFloat
    let symbol: String
    var platform: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteArtwork(urlString: artwork, cornerRadius: 10, symbol: symbol)
                .frame(width: side, height: side)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .compositingGroup()
            HStack(spacing: 5) {
                if let platform, PlatformBrand.assetName(for: platform) != nil {
                    PlatformBrandMark(platform: platform, size: 16)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(.rect(cornerRadius: 10, style: .continuous))
        .clipped(antialiased: true)
    }
}
