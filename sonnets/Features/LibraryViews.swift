import SwiftUI
import UniformTypeIdentifiers
import MediaPlayer
import UIKit

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @State private var showCreatePlaylist = false
    @State private var playlistName = ""
    @State private var showFileImporter = false

    var body: some View {
        ZStack {
            AppBackground()
            List {
                Section {
                    NavigationLink { TrackCollectionView(title: String(localized: "我的收藏"), tracks: library.favorites, symbol: "heart.fill") } label: {
                        libraryLink(title: String(localized: "我的收藏"), subtitle: localizedSongCount(library.favorites.count), symbol: "heart.fill", color: .pink)
                    }
                    NavigationLink { DownloadsView() } label: {
                        libraryLink(title: String(localized: "已下载"), subtitle: localizedSongCount(library.downloads.count), symbol: "arrow.down", color: .blue)
                    }
                    NavigationLink { HistoryView() } label: {
                        libraryLink(
                            title: String(localized: "播放历史"),
                            subtitle: String(format: String(localized: "%d 条"), library.history.count),
                            symbol: "clock.fill",
                            color: .orange
                        )
                    }
                }
                .listRowBackground(Color.clear)

                Section("歌单") {
                    ForEach(library.playlists) { playlist in
                        NavigationLink { LocalPlaylistDetailView(playlistID: playlist.id) } label: {
                            HStack(spacing: 12) {
                                RemoteArtwork(urlString: playlist.artwork ?? playlist.tracks.first?.artwork, cornerRadius: 10, symbol: "music.note.list")
                                    .frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                    Text(localizedSongCount(playlist.tracks.count)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { library.deletePlaylist(playlist) }
                        }
                    }
                    Button { showCreatePlaylist = true } label: { Label("新建歌单", systemImage: "plus.circle.fill") }
                    Button { showFileImporter = true } label: { Label("导入本地音乐", systemImage: "folder.badge.plus") }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("音乐库")
        .alert("新建歌单", isPresented: $showCreatePlaylist) {
            TextField("歌单名称", text: $playlistName)
            Button("取消", role: .cancel) { playlistName = "" }
            Button("创建") {
                _ = library.createPlaylist(name: playlistName)
                playlistName = ""
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { Task { _ = await library.importLocalFiles(urls) } }
        }
    }

    private func libraryLink(title: String, subtitle: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.gradient)
                Image(systemName: symbol).foregroundStyle(.white).font(.title3)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func localizedSongCount(_ count: Int) -> String {
        String(format: String(localized: "%d 首"), count)
    }
}

struct LocalPlaylistDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    let playlistID: UUID
    @State private var showRename = false
    @State private var newName = ""

    var body: some View {
        Group {
            if let playlist = library.playlist(id: playlistID) {
                ZStack {
                    AppBackground()
                    List {
                        LocalPlaylistHero(
                            playlist: playlist,
                            play: { player.playAll(playlist.tracks) },
                            shuffle: { player.playShuffled(playlist.tracks) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        if playlist.tracks.isEmpty {
                            EmptyContentView(title: "歌单为空", message: "可从搜索结果中添加歌曲", symbol: "music.note")
                                .listRowBackground(Color.clear)
                        }
                        ForEach(playlist.tracks) { track in
                            MusicRow(track: track, tracks: playlist.tracks)
                                .listRowBackground(Color.clear)
                                .swipeActions { Button("移除", role: .destructive) { library.remove(track, from: playlist) } }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .ignoresSafeArea(edges: .top)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("重命名", systemImage: "pencil") { newName = playlist.name; showRename = true }
                            ShareLink(item: playlist.name)
                            Button("删除歌单", systemImage: "trash", role: .destructive) { library.deletePlaylist(playlist) }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .alert("重命名歌单", isPresented: $showRename) {
                    TextField("歌单名称", text: $newName)
                    Button("取消", role: .cancel) {}
                    Button("保存") { library.renamePlaylist(playlist, name: newName) }
                }
            } else {
                EmptyContentView(title: "歌单不存在", message: "它可能已被删除", symbol: "questionmark.folder")
            }
        }
    }
}

private struct LocalPlaylistHero: View {
    let playlist: LocalPlaylist
    let play: () -> Void
    let shuffle: () -> Void
    @State private var dominantColor = Color(red: 0.10, green: 0.11, blue: 0.14)

    private var artwork: String? {
        playlist.artwork ?? playlist.tracks.first?.artwork
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                dominantColor

                RemoteArtwork(
                    urlString: artwork,
                    cornerRadius: 0,
                    symbol: "music.note.list"
                )
                .frame(width: proxy.size.width, height: 560)

                RemoteArtwork(
                    urlString: artwork,
                    cornerRadius: 0,
                    symbol: "music.note.list"
                )
                .frame(width: proxy.size.width, height: 560)
                .blur(radius: 32)
                .scaleEffect(1.14)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: .black.opacity(0.34), location: 0.58),
                            .init(color: .black, location: 0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .clear, location: 0.20),
                        .init(color: .clear, location: 0.43),
                        .init(color: dominantColor.opacity(0.34), location: 0.58),
                        .init(color: dominantColor.opacity(0.92), location: 0.78),
                        .init(color: dominantColor, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 13) {
                    Text(playlist.name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.96))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)

                    Text("本地歌单")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.90))

                    Text("Sonnets · 本地")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))

                    HStack(spacing: 18) {
                        Button(action: shuffle) {
                            Image(systemName: "shuffle")
                                .font(.title3.weight(.semibold))
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(.plain)
                        .background(.white.opacity(0.14), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 0.8) }

                        Button(action: play) {
                            Label("播放", systemImage: "play.fill")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .foregroundStyle(dominantColor)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: playlist.name) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3.weight(.semibold))
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(.plain)
                        .background(.white.opacity(0.14), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 0.8) }
                    }
                    .disabled(playlist.tracks.isEmpty)
                    .opacity(playlist.tracks.isEmpty ? 0.48 : 1)
                    .padding(.top, 12)

                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
            .frame(width: proxy.size.width, height: 560)
            .clipped()
        }
        .frame(height: 560)
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

struct TrackCollectionView: View {
    @Environment(PlayerService.self) private var player
    let title: String
    let tracks: [MusicItem]
    let symbol: String

    var body: some View {
        ZStack {
            AppBackground()
            List {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.gradient)
                        Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(.white)
                    }
                    .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title).font(.title2.bold())
                        Text("\(tracks.count) 首").foregroundStyle(.secondary)
                        Button { player.playAll(tracks) } label: { Label("播放全部", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                            .disabled(tracks.isEmpty)
                    }
                }
                .padding(.vertical)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(tracks) { MusicRow(track: $0, tracks: tracks).listRowBackground(Color.clear) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ZStack {
            AppBackground()
            if library.history.isEmpty {
                EmptyContentView(title: "暂无播放历史", message: "播放过的歌曲会出现在这里", symbol: "clock")
            } else {
                List(library.history) { entry in
                    MusicRow(track: entry.track, tracks: library.history.map(\.track))
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("播放历史")
        .toolbar { if !library.history.isEmpty { Button("清空", role: .destructive) { library.clearHistory() } } }
    }
}

struct DownloadsView: View {
    @Environment(LibraryStore.self) private var library
    var body: some View {
        ZStack {
            AppBackground()
            if library.downloads.isEmpty && library.activeDownloads.isEmpty {
                EmptyContentView(title: "暂无下载", message: "在歌曲菜单中选择下载，之后可离线播放", symbol: "arrow.down.circle")
            } else {
                List {
                    ForEach(Array(library.activeDownloads).sorted(), id: \.self) { id in
                        HStack(spacing: 12) {
                            if let track = library.activeDownloadTrack(for: id) {
                                RemoteArtwork(urlString: track.artwork, cornerRadius: 8)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title).lineLimit(1)
                                    Text("正在下载…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("正在下载…")
                            }
                            Spacer()
                            ProgressView()
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(library.downloads) { download in
                        MusicRow(track: download.track, tracks: library.downloads.map(\.track))
                            .listRowBackground(Color.clear)
                            .swipeActions { Button("删除", role: .destructive) { library.deleteDownload(download) } }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("已下载")
        .alert(
            "下载失败",
            isPresented: Binding(
                get: { library.lastError != nil },
                set: { if !$0 { library.lastError = nil } }
            )
        ) {
            Button("好") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? String(localized: "未知错误"))
        }
    }
}

struct QueueView: View {
    @Environment(PlayerService.self) private var player
    var body: some View {
        ZStack {
            AppBackground()
            if player.queue.isEmpty {
                EmptyContentView(title: "播放队列为空", message: "播放一首歌曲后可在这里管理顺序", symbol: "text.line.last.and.arrowtriangle.forward")
            } else {
                List {
                    ForEach(player.queue) { track in
                        MusicRow(track: track, tracks: player.queue)
                            .listRowBackground(player.currentTrack?.stableID == track.stableID ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .onMove(perform: player.moveQueueItems)
                    .onDelete(perform: player.removeQueueItems)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("播放队列")
        .toolbar { EditButton() }
    }
}

struct ImportPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginManager.self) private var plugins
    @Environment(LibraryStore.self) private var library
    @State private var text = ""
    @State private var selectedPluginID: UUID?
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var showAppleMusicPicker = false

    private var capablePlugins: [InstalledPlugin] {
        plugins.enabledPlugins.filter { $0.manifest.supportedMethods.contains("importMusicSheet") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("从设备导入") {
                    Button {
                        showFileImporter = true
                    } label: {
                        ImportSourceLabel(
                            title: String(localized: "本地音乐文件"),
                            subtitle: String(localized: "支持一次选择多个音频文件"),
                            symbol: "folder.badge.plus"
                        )
                    }

                    Button {
                        requestAppleMusicAccess()
                    } label: {
                        ImportSourceLabel(
                            title: "Apple Music",
                            subtitle: String(localized: "从你的音乐资料库选择歌曲"),
                            symbol: "apple.logo"
                        )
                    }
                }

                Section("从歌单链接导入") {
                    Picker("使用插件", selection: $selectedPluginID) {
                        Text("自动识别平台").tag(UUID?.none)
                        ForEach(capablePlugins) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("粘贴目标歌单链接", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await importPlaylist() }
                    } label: {
                        HStack {
                            Spacer()
                            if isImporting { ProgressView() } else { Text("导入歌单") }
                            Spacer()
                        }
                    }
                    .disabled(isImporting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("导入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    let tracks = await library.importLocalFiles(urls)
                    if tracks.isEmpty {
                        errorMessage = library.lastError ?? String(localized: "没有可导入的音频文件")
                    } else {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showAppleMusicPicker) {
                AppleMusicPicker(isPresented: $showAppleMusicPicker) { items in
                    let tracks = library.importAppleMusicItems(items)
                    if tracks.isEmpty {
                        errorMessage = String(localized: "没有选择可导入的歌曲")
                    } else {
                        dismiss()
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func importPlaylist() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let tracks: [MusicItem]
            if let selectedPluginID {
                tracks = try await plugins.importPlaylist(text, using: selectedPluginID)
            } else {
                tracks = try await plugins.importPlaylistAutomatically(text)
            }
            guard !tracks.isEmpty else { throw PluginRuntimeError.invalidResponse }
            let name = String(
                format: String(localized: "导入歌单 · %@"),
                Date.now.formatted(date: .numeric, time: .omitted)
            )
            _ = library.createPlaylist(name: name, tracks: tracks)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func requestAppleMusicAccess() {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized:
            showAppleMusicPicker = true
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        showAppleMusicPicker = true
                    } else {
                        errorMessage = String(localized: "需要允许访问媒体资料库才能导入 Apple Music")
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = String(localized: "请在系统设置中允许 Sonnets 访问媒体与 Apple Music")
        @unknown default:
            errorMessage = String(localized: "当前无法访问 Apple Music 资料库")
        }
    }
}

private struct ImportSourceLabel: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
        }
        .padding(.vertical, 3)
    }
}

private struct AppleMusicPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: ([MPMediaItem]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.delegate = context.coordinator
        picker.allowsPickingMultipleItems = true
        picker.showsCloudItems = true
        picker.showsItemsWithProtectedAssets = true
        picker.prompt = String(localized: "选择要导入 Sonnets 的歌曲")
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        var parent: AppleMusicPicker

        init(parent: AppleMusicPicker) { self.parent = parent }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            parent.onPick(mediaItemCollection.items)
            parent.isPresented = false
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            parent.isPresented = false
        }
    }
}
