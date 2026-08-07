import SwiftUI
import Observation

enum AppTab: Hashable {
    case home
    case search
    case library
    case settings
}

struct PlayerContainerView: View {
    @Environment(PluginManager.self) private var plugins
    @Environment(PlayerService.self) private var player
    @State private var isNowPlayingPresented = false
    @State private var homeDiscovery = HomeDiscoveryStore()
    @State private var playbackTheme = PlaybackTheme()

    var body: some View {
        ContentView(
            homeDiscovery: homeDiscovery,
            onOpenNowPlaying: presentNowPlaying
        )
        .environment(playbackTheme)
        .fullScreenCover(isPresented: $isNowPlayingPresented) {
            NowPlayingView()
                .environment(playbackTheme)
        }
        .task {
            await plugins.bootstrap()
        }
        .task(id: plugins.selectedPluginID) {
            await homeDiscovery.loadDiscovery(using: plugins)
        }
        .task(id: player.currentTrack?.artwork) {
            await playbackTheme.update(for: player.currentTrack?.artwork)
        }
    }

    private func presentNowPlaying() {
        guard player.currentTrack != nil, !isNowPlayingPresented else { return }
        isNowPlayingPresented = true
    }
}

@MainActor
@Observable
final class SearchCoordinator {
    var draft = ""
    private(set) var submittedQuery = ""
    private(set) var requestID = UUID()

    func submit(_ value: String? = nil) {
        let candidate = (value ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        submittedQuery = candidate
        requestID = UUID()
        draft = ""
    }

    func reset() {
        draft = ""
        submittedQuery = ""
        requestID = UUID()
    }
}

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerService.self) private var player
    @Environment(PlaybackTheme.self) private var playbackTheme
    @State private var selectedTab: AppTab = .home
    @State private var search = SearchCoordinator()
    @State private var isSearchChromeCompact = false
    let homeDiscovery: HomeDiscoveryStore
    let onOpenNowPlaying: () -> Void

    init(
        homeDiscovery: HomeDiscoveryStore,
        onOpenNowPlaying: @escaping () -> Void = {}
    ) {
        self.homeDiscovery = homeDiscovery
        self.onOpenNowPlaying = onOpenNowPlaying
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                appTabs
                    .toolbar(selectedTab == .search ? .hidden : .visible, for: .tabBar)
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory(
                        isEnabled: selectedTab != .search && player.currentTrack != nil
                    ) {
                        TabAccessoryMiniPlayer(onOpen: onOpenNowPlaying)
                    }
                    .overlay(alignment: .bottom) {
                        if selectedTab == .search {
                            SearchBottomChrome(
                                search: search,
                                compact: isSearchChromeCompact && player.currentTrack != nil,
                                onSelectHome: { selectedTab = .home },
                                onExpand: setSearchChromeExpanded,
                                onOpenNowPlaying: onOpenNowPlaying
                            )
                        }
                    }
            } else {
                appTabs
                    .toolbar(selectedTab == .search ? .hidden : .visible, for: .tabBar)
                    .overlay(alignment: .bottom) {
                        if selectedTab == .search {
                            SearchBottomChrome(
                                search: search,
                                compact: isSearchChromeCompact && player.currentTrack != nil,
                                onSelectHome: { selectedTab = .home },
                                onExpand: setSearchChromeExpanded,
                                onOpenNowPlaying: onOpenNowPlaying
                            )
                        } else if player.currentTrack != nil {
                            MiniPlayer(onOpen: onOpenNowPlaying)
                                .padding(.bottom, 62)
                        }
                    }
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.86), value: player.currentTrack?.stableID)
        .preferredColorScheme(preferredColorScheme)
    }

    private var appTabs: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house.fill", value: .home) {
                NavigationStack { HomeView(discovery: homeDiscovery) }
            }
            Tab("搜索", systemImage: "magnifyingglass", value: .search, role: .search) {
                NavigationStack {
                    SearchView(
                        search: search,
                        onChromeCompactChange: updateSearchChrome
                    )
                }
            }
            Tab("音乐库", systemImage: "music.note.list", value: .library) {
                NavigationStack { LibraryView() }
            }
            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(playbackTheme.accent)
        .animation(.easeInOut(duration: 0.32), value: playbackTheme.accent)
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private func updateSearchChrome(_ compact: Bool) {
        let compact = compact && player.currentTrack != nil
        guard compact != isSearchChromeCompact else { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
            isSearchChromeCompact = compact
        }
    }

    private func setSearchChromeExpanded() {
        updateSearchChrome(false)
    }

}

private struct SearchBottomChrome: View {
    @Environment(PlayerService.self) private var player
    let search: SearchCoordinator
    let compact: Bool
    let onSelectHome: () -> Void
    let onExpand: () -> Void
    let onOpenNowPlaying: () -> Void

    @FocusState private var searchFocused: Bool
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    chromeLayout
                }
            } else {
                chromeLayout
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.46, dampingFraction: 0.84), value: compact)
    }

    @ViewBuilder
    private var chromeLayout: some View {
        if compact, player.currentTrack != nil {
            HStack(spacing: 10) {
                homeButton
                searchMiniPlayer(compact: true)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                compactSearchButton
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                if player.currentTrack != nil {
                    searchMiniPlayer(compact: false)
                        .frame(maxWidth: .infinity)
                }

                HStack(spacing: 10) {
                    homeButton
                    searchField
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                    closeSearchButton
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var homeButton: some View {
        chromeCircleButton(symbol: "house.fill", label: String(localized: "首页"), action: onSelectHome)
    }

    private var compactSearchButton: some View {
        chromeCircleButton(symbol: "magnifyingglass", label: String(localized: "展开搜索")) {
            onExpand()
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
            }
        }
    }

    private var closeSearchButton: some View {
        let hasQuery = !search.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return chromeCircleButton(
            symbol: hasQuery ? "magnifyingglass" : "xmark",
            label: hasQuery ? String(localized: "搜索") : String(localized: "清除搜索并收起键盘")
        ) {
            if hasQuery {
                submitSearch()
            } else {
                search.reset()
                searchFocused = false
            }
        }
    }

    private var searchField: some View {
        @Bindable var search = search
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("歌曲、歌手、专辑或歌单", text: $search.draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { submitSearch() }
                .accessibilityIdentifier("global-search-field")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .modifier(SearchChromeGlassModifier(shape: .capsule, id: "search-field", namespace: glassNamespace))
        .contentShape(.capsule)
        .onTapGesture { searchFocused = true }
    }

    private func searchMiniPlayer(compact: Bool) -> some View {
        MiniPlayer(
            onOpen: onOpenNowPlaying,
            embeddedInTabBar: true,
            compact: compact
        )
        .modifier(SearchChromeGlassModifier(shape: .capsule, id: "search-player", namespace: glassNamespace))
    }

    private func chromeCircleButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .contentShape(.circle)
        }
        .buttonStyle(PlayerPressFeedbackStyle(pressedScale: 0.84))
        .modifier(SearchChromeGlassModifier(shape: .circle, id: label, namespace: glassNamespace))
        .accessibilityLabel(label)
    }

    private func submitSearch() {
        guard !search.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchFocused = false
        search.submit()
    }
}

private struct SearchChromeGlassModifier: ViewModifier {
    enum Shape {
        case capsule
        case circle
    }

    let shape: Shape
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .capsule:
                content
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .glassEffectID(id, in: namespace)
            case .circle:
                content
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID(id, in: namespace)
            }
        } else {
            switch shape {
            case .capsule:
                content.background(.ultraThinMaterial, in: Capsule())
            case .circle:
                content.background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

#Preview {
    let plugins = PluginManager()
    let library = LibraryStore()
    let settings = AppSettings()
    let player = PlayerService(pluginManager: plugins, library: library, settings: settings)
    PlayerContainerView()
        .environment(plugins)
        .environment(library)
        .environment(settings)
        .environment(player)
}
