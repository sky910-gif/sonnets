import SwiftUI

struct SearchView: View {
    @Environment(PluginManager.self) private var plugins
    @Environment(PlayerService.self) private var player
    let search: SearchCoordinator
    let onChromeCompactChange: (Bool) -> Void
    @AppStorage("searchHistory") private var searchHistoryData = Data()
    @State private var mediaType: MediaType = .music
    @State private var selectedPluginID: UUID?
    @State private var results: [SearchResultItem] = []
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var page = 1
    @State private var canLoadMore = false
    @State private var errorMessage: String?

    private let filterBarHeight: CGFloat = 92
    private let resultTopInset: CGFloat = 144

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            resultsContent
        }
        .overlay(alignment: .top) { searchFilterBar }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if selectedPluginID == nil,
               let preferred = plugins.selectedPluginID,
               availablePlugins.contains(where: { $0.id == preferred }) {
                selectedPluginID = preferred
            }
        }
        .onChange(of: plugins.selectedPluginID) { _, preferred in
            guard selectedPluginID == nil,
                  let preferred,
                  availablePlugins.contains(where: { $0.id == preferred }) else { return }
            selectedPluginID = preferred
        }
        .onChange(of: mediaType) { _, _ in validateSelectedPlugin() }
        .task(id: SearchKey(query: search.submittedQuery, type: mediaType, pluginID: selectedPluginID, requestToken: search.requestID)) {
            await runSearch()
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if search.submittedQuery.isEmpty {
            initialSearchContent
        } else if isSearching && results.isEmpty {
            ProgressView("正在从 \(selectedPluginName) 搜索…")
                .frame(maxHeight: .infinity)
                .padding(.top, resultTopInset)
        } else if let errorMessage, results.isEmpty {
            ContentUnavailableView("搜索失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                .frame(maxHeight: .infinity)
                .padding(.top, resultTopInset)
        } else if results.isEmpty {
            EmptyContentView(title: "没有结果", message: "换一个关键词或音乐平台试试", symbol: "magnifyingglass")
                .frame(maxHeight: .infinity)
                .padding(.top, resultTopInset)
        } else {
            resultsList
        }
    }

    @ViewBuilder
    private var initialSearchContent: some View {
        if searchHistory.isEmpty {
            BundledLottieAnimation(name: "walking_dog")
                .frame(width: 168, height: 168)
                .accessibilityLabel("等待搜索")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, filterBarHeight)
                .allowsHitTesting(false)
        } else {
            List {
                Color.clear
                    .frame(height: filterBarHeight)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)

                Section {
                    ForEach(searchHistory, id: \.self) { term in
                        Button {
                            submitSearch(term)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(term)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                removeSearchHistory(term)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("搜索历史")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Spacer()
                        Button("清除") { clearSearchHistory() }
                            .font(.subheadline)
                            .textCase(nil)
                    }
                    .padding(.bottom, 4)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(SearchChromeScrollTracker(onCompactChange: onChromeCompactChange))
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: player.currentTrack == nil ? 64 : 126)
            }
        }
    }

    private var searchFilterBar: some View {
        VStack(spacing: 0) {
            platformPicker
            mediaTypePicker
        }
        .frame(height: filterBarHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(.black.opacity(0.78))
                LinearGradient(
                    colors: [.white.opacity(0.035), .black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.black.opacity(0.78))
            .mask {
                LinearGradient(
                    colors: [.white, .white.opacity(0.56), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(height: 52)
            .offset(y: 52)
            .allowsHitTesting(false)
        }
        .zIndex(2)
    }

    private var platformPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Group {
                    if #available(iOS 26.0, *) {
                        GlassEffectContainer(spacing: 6) { platformChips }
                    } else {
                        platformChips
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 42)
        }
        .padding(.vertical, 6)
    }

    private var mediaTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(MediaType.allCases) { type in
                    SearchCategoryChip(title: type.title, selected: mediaType == type) {
                        mediaType = type
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 38)
        .padding(.bottom, 5)
    }

    private var platformChips: some View {
        LazyHStack(spacing: 8) {
            SearchPlatformChip(title: String(localized: "全部"), selected: selectedPluginID == nil) {
                selectedPluginID = nil
            }
            ForEach(availablePlugins) { plugin in
                SearchPlatformChip(title: plugin.name, platform: plugin.name, selected: selectedPluginID == plugin.id) {
                    selectedPluginID = plugin.id
                    plugins.selectedPluginID = plugin.id
                }
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear
                    .frame(height: resultTopInset)
                    .accessibilityHidden(true)

                ForEach(results) { result in
                    VStack(spacing: 0) {
                        resultRow(result)
                            .padding(.vertical, 6)
                            .padding(.leading, 16)
                            .padding(.trailing, 10)

                        Divider()
                            .padding(.leading, 76)
                    }
                    .onAppear {
                        if result.id == results.last?.id, canLoadMore { Task { await loadMore() } }
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
        // Keep the vertical scroller bounded to the tab's viewport. The system
        // tab bar uses this scroll view to drive its minimize/accessory placement.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollDismissesKeyboard(.immediately)
        .modifier(SearchChromeScrollTracker(onCompactChange: onChromeCompactChange))
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: player.currentTrack == nil ? 64 : 126)
        }
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResultItem) -> some View {
        switch result {
        case .music(let track):
            MusicRow(track: track, tracks: musicResults)
                .padding(.vertical, 3)
        case .album(let album):
            NavigationLink { AlbumDetailView(album: album) } label: {
                mediaRow(title: album.title, subtitle: album.artist, artwork: album.artwork, symbol: "square.stack")
            }
        case .artist(let artist):
            NavigationLink { ArtistDetailView(artist: artist) } label: {
                mediaRow(title: artist.name, subtitle: artist.platform, artwork: artist.avatar, symbol: "person.fill", circular: true)
            }
        case .sheet(let playlist):
            NavigationLink { RemotePlaylistDetailView(playlist: playlist) } label: {
                mediaRow(title: playlist.title, subtitle: [playlist.artist, playlist.platform].filter { !$0.isEmpty }.joined(separator: " · "), artwork: playlist.artwork, symbol: "music.note.list")
            }
        case .lyric(let lyric):
            VStack(alignment: .leading, spacing: 7) {
                MusicRow(track: lyric.music, tracks: lyricResults)
                if !lyric.preview.isEmpty {
                    Text(lyric.preview.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 60)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func mediaRow(title: String, subtitle: String, artwork: String?, symbol: String, circular: Bool = false) -> some View {
        HStack(spacing: 12) {
            RemoteArtwork(urlString: artwork, cornerRadius: circular ? 28 : 10, symbol: symbol)
                .frame(width: 54, height: 54)
                .clipped()
                .fixedSize()
                .layoutPriority(2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.vertical, 3)
    }

    private var musicResults: [MusicItem] {
        results.compactMap { if case .music(let item) = $0 { item } else { nil } }
    }

    private var lyricResults: [MusicItem] {
        results.compactMap { if case .lyric(let item) = $0 { item.music } else { nil } }
    }

    private var selectedPluginName: String {
        guard let selectedPluginID else { return String(localized: "全部平台") }
        return plugins.enabledPlugins.first(where: { $0.id == selectedPluginID })?.name ?? String(localized: "全部")
    }

    private var availablePlugins: [InstalledPlugin] {
        plugins.enabledPlugins.filter { $0.manifest.supportedSearchTypes.contains(mediaType) }
    }

    private var searchHistory: [String] {
        (try? JSONDecoder().decode([String].self, from: searchHistoryData)) ?? []
    }

    private func validateSelectedPlugin() {
        guard let selectedPluginID else { return }
        if !availablePlugins.contains(where: { $0.id == selectedPluginID }) {
            let fallbackID = availablePlugins.first?.id
            self.selectedPluginID = fallbackID
            plugins.selectedPluginID = fallbackID
        }
    }

    private func runSearch() async {
        let trimmed = search.submittedQuery
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            canLoadMore = false
            return
        }
        isSearching = true
        defer {
            if search.submittedQuery == trimmed {
                isSearching = false
            }
        }
        errorMessage = nil
        page = 1
        rememberSearch(trimmed)
        do {
            let newResults = try await plugins.search(query: trimmed, page: 1, type: mediaType, pluginID: selectedPluginID)
            guard !Task.isCancelled else { return }
            results = newResults
            canLoadMore = newResults.count >= 10
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func rememberSearch(_ term: String) {
        var updated = searchHistory.filter { $0.localizedCaseInsensitiveCompare(term) != .orderedSame }
        updated.insert(term, at: 0)
        searchHistoryData = (try? JSONEncoder().encode(Array(updated.prefix(12)))) ?? Data()
    }

    private func removeSearchHistory(_ term: String) {
        let updated = searchHistory.filter { $0 != term }
        searchHistoryData = (try? JSONEncoder().encode(updated)) ?? Data()
    }

    private func clearSearchHistory() {
        searchHistoryData = Data()
    }

    private func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = page + 1
        do {
            let more = try await plugins.search(query: search.submittedQuery, page: nextPage, type: mediaType, pluginID: selectedPluginID)
            let existing = Set(results.map(\.id))
            let unique = more.filter { !existing.contains($0.id) }
            results += unique
            page = nextPage
            canLoadMore = !unique.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    private func submitSearch(_ term: String? = nil) {
        search.submit(term)
    }
}

private struct SearchChromeScrollTracker: ViewModifier {
    let onCompactChange: (Bool) -> Void

    @State private var lastOffset: CGFloat?
    @State private var accumulatedDelta: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { oldOffset, newOffset in
                update(oldOffset: oldOffset, newOffset: newOffset)
            }
    }

    private func update(oldOffset: CGFloat, newOffset: CGFloat) {
        if newOffset <= 2 {
            accumulatedDelta = 0
            lastOffset = newOffset
            onCompactChange(false)
            return
        }

        let previous = lastOffset ?? oldOffset
        let delta = newOffset - previous
        lastOffset = newOffset
        guard abs(delta) < 80 else {
            accumulatedDelta = 0
            return
        }

        if accumulatedDelta == 0 || accumulatedDelta.sign == delta.sign {
            accumulatedDelta += delta
        } else {
            accumulatedDelta = delta
        }

        if accumulatedDelta > 18 {
            accumulatedDelta = 0
            onCompactChange(true)
        } else if accumulatedDelta < -18 {
            accumulatedDelta = 0
            onCompactChange(false)
        }
    }
}

private struct SearchPlatformChip: View {
    let title: String
    var platform: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let platform {
                    PlatformBrandMark(platform: platform, size: 18)
                }
                if selected { Image(systemName: "checkmark").font(.caption2.bold()) }
                Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .modifier(SearchPlatformChipStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SearchCategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .medium))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.white.opacity(0.68))
        .background(
            selected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.07),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(selected ? Color.accentColor.opacity(0.30) : Color.white.opacity(0.10), lineWidth: 0.7)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SearchPlatformChipStyle: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if selected {
                content
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
            } else {
                content
                    .foregroundStyle(.white.opacity(0.84))
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            content
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.84))
                .background(selected ? Color.accentColor : Color.white.opacity(0.10), in: Capsule())
        }
    }
}

private struct SearchKey: Hashable {
    var query: String
    var type: MediaType
    var pluginID: UUID?
    var requestToken: UUID
}
