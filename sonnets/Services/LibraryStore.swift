import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit
import UniformTypeIdentifiers

struct DownloadedTrack: Codable, Hashable, Identifiable, Sendable {
    var track: MusicItem
    var localFilename: String
    var downloadedAt: Date
    var byteCount: Int64?
    var quality: AudioQuality?
    var id: String { track.stableID }
}

private enum MusicDownloadError: LocalizedError {
    case invalidResponse
    case unsupportedContent(String)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "下载服务器返回了无效响应")
        case .unsupportedContent(let type):
            String(localized: "下载内容不是可播放音频（\(type)）")
        case .emptyFile:
            String(localized: "下载文件为空")
        }
    }
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var favorites: [MusicItem] = []
    private(set) var playlists: [LocalPlaylist] = []
    private(set) var history: [PlaybackHistoryEntry] = []
    private(set) var downloads: [DownloadedTrack] = []
    private(set) var activeDownloads: Set<String> = []
    private(set) var activeDownloadTracks: [String: MusicItem] = [:]
    var lastError: String?

    private let fileManager = FileManager.default
    private let persistenceQueue = DispatchQueue(label: "langlai.sonnets.library-persistence", qos: .utility)

    private var rootDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Sonnets", directoryHint: .isDirectory)
    }
    private var libraryURL: URL { rootDirectory.appending(path: "library.json") }
    private var downloadsDirectory: URL { rootDirectory.appending(path: "Downloads", directoryHint: .isDirectory) }
    private var localMusicDirectory: URL { rootDirectory.appending(path: "Local Music", directoryHint: .isDirectory) }

    init() {
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: localMusicDirectory, withIntermediateDirectories: true)
        load()
    }

    func isFavorite(_ track: MusicItem) -> Bool {
        favorites.contains { $0.stableID == track.stableID }
    }

    func toggleFavorite(_ track: MusicItem) {
        if isFavorite(track) {
            favorites.removeAll { $0.stableID == track.stableID }
        } else {
            favorites.insert(track, at: 0)
        }
        persist()
    }

    @discardableResult
    func createPlaylist(name: String, tracks: [MusicItem] = []) -> LocalPlaylist {
        let playlist = LocalPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "新建歌单") : name, tracks: unique(tracks))
        playlists.insert(playlist, at: 0)
        persist()
        return playlist
    }

    func deletePlaylist(_ playlist: LocalPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        persist()
    }

    func renamePlaylist(_ playlist: LocalPlaylist, name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = name
        persist()
    }

    func add(_ tracks: [MusicItem], to playlist: LocalPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].tracks = unique(playlists[index].tracks + tracks)
        if playlists[index].artwork == nil { playlists[index].artwork = tracks.first?.artwork }
        persist()
    }

    func remove(_ track: MusicItem, from playlist: LocalPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].tracks.removeAll { $0.stableID == track.stableID }
        persist()
    }

    func playlist(id: UUID) -> LocalPlaylist? { playlists.first { $0.id == id } }

    func recordPlayed(_ track: MusicItem) {
        history.removeAll { $0.track.stableID == track.stableID }
        history.insert(PlaybackHistoryEntry(track: track, playedAt: .now), at: 0)
        history = Array(history.prefix(300))
        persist()
    }

    func clearHistory() {
        history = []
        persist()
    }

    func localURL(for track: MusicItem) -> URL? {
        if let download = downloads.first(where: { $0.track.stableID == track.stableID }) {
            let url = downloadsDirectory.appending(path: download.localFilename)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        if let value = track.raw.string("localURL"), let url = URL(string: value) {
            if url.scheme == "ipod-library" || fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func isDownloaded(_ track: MusicItem) -> Bool { localURL(for: track) != nil }

    func download(_ track: MusicItem, using plugins: PluginManager, quality: AudioQuality) async {
        guard !activeDownloads.contains(track.stableID) else { return }
        activeDownloads.insert(track.stableID)
        activeDownloadTracks[track.stableID] = track
        lastError = nil
        defer {
            activeDownloads.remove(track.stableID)
            activeDownloadTracks[track.stableID] = nil
        }

        do {
            let resolvedTrack = await plugins.musicInfo(for: track)
            activeDownloadTracks[track.stableID] = resolvedTrack
            let source = try await plugins.mediaSource(for: resolvedTrack, quality: quality)
            try await storeDownload(resolvedTrack, source: source)
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Kept for callers that have already resolved a media source.
    func download(_ track: MusicItem, source: MediaSource) async {
        guard !activeDownloads.contains(track.stableID) else { return }
        activeDownloads.insert(track.stableID)
        activeDownloadTracks[track.stableID] = track
        lastError = nil
        defer {
            activeDownloads.remove(track.stableID)
            activeDownloadTracks[track.stableID] = nil
        }
        do {
            try await storeDownload(track, source: source)
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }

    func activeDownloadTrack(for id: String) -> MusicItem? {
        activeDownloadTracks[id]
    }

    private func storeDownload(_ track: MusicItem, source: MediaSource) async throws {
        var request = URLRequest(
            url: source.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 180
        )
        source.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("audio/*,application/octet-stream;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw MusicDownloadError.invalidResponse
        }
        if let mimeType = http.mimeType?.lowercased(),
           mimeType.hasPrefix("text/") || mimeType.contains("json") || mimeType.contains("html") {
            throw MusicDownloadError.unsupportedContent(mimeType)
        }

        let attributes = try fileManager.attributesOfItem(atPath: temporaryURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount > 0 else { throw MusicDownloadError.emptyFile }

        let fileExtension = preferredExtension(source: source, response: response)
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let destination = downloadsDirectory.appending(path: filename)
        try fileManager.moveItem(at: temporaryURL, to: destination)

        if let previous = downloads.first(where: { $0.track.stableID == track.stableID }) {
            try? fileManager.removeItem(at: downloadsDirectory.appending(path: previous.localFilename))
        }
        downloads.removeAll { $0.track.stableID == track.stableID }
        downloads.insert(
            DownloadedTrack(
                track: track,
                localFilename: filename,
                downloadedAt: .now,
                byteCount: byteCount,
                quality: source.quality
            ),
            at: 0
        )
        persist()
    }

    private func preferredExtension(source: MediaSource, response: URLResponse) -> String {
        let candidates = [
            response.suggestedFilename.flatMap { URL(fileURLWithPath: $0).pathExtension },
            response.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension },
            source.url.pathExtension
        ]
        for candidate in candidates {
            let cleaned = candidate?
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            if let cleaned, !cleaned.isEmpty, cleaned.count <= 8 { return cleaned }
        }
        return "m4a"
    }

    func deleteDownload(_ download: DownloadedTrack) {
        try? fileManager.removeItem(at: downloadsDirectory.appending(path: download.localFilename))
        downloads.removeAll { $0.id == download.id }
        persist()
    }

    func importLocalFiles(_ urls: [URL]) async -> [MusicItem] {
        var imported: [MusicItem] = []
        for sourceURL in urls {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                let ext = sourceURL.pathExtension
                let destination = localMusicDirectory.appending(path: "\(UUID().uuidString).\(ext)")
                try fileManager.copyItem(at: sourceURL, to: destination)
                let asset = AVURLAsset(url: destination)
                let duration = try? await asset.load(.duration).seconds
                let item = MusicItem(raw: [
                    "id": .string(UUID().uuidString),
                    "platform": .string(String(localized: "本地音乐")),
                    "title": .string(sourceURL.deletingPathExtension().lastPathComponent),
                    "artist": .string(String(localized: "本地音乐")),
                    "album": .string(String(localized: "本地导入")),
                    "duration": .number(duration ?? 0),
                    "url": .string(destination.absoluteString),
                    "localURL": .string(destination.absoluteString)
                ])
                imported.append(item)
            } catch {
                lastError = error.localizedDescription
            }
        }
        if !imported.isEmpty {
            let localizedName = String(localized: "本地音乐")
            let defaultNames = Set([localizedName, "本地音乐", "Local Music"])
            let target = playlists.first(where: { defaultNames.contains($0.name) }) ?? createPlaylist(name: localizedName)
            add(imported, to: target)
        }
        return imported
    }

    func importAppleMusicItems(_ mediaItems: [MPMediaItem]) -> [MusicItem] {
        let existingTracks = Dictionary(
            playlists
                .flatMap(\.tracks)
                .filter { $0.raw.string("appleMusicPersistentID") != nil }
                .map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        let imported = mediaItems.map { mediaItem in
            let persistentID = String(mediaItem.persistentID)
            var raw: [String: JSONValue] = [
                "id": .string(persistentID),
                "appleMusicPersistentID": .string(persistentID),
                "platform": .string("Apple Music"),
                "title": .string(mediaItem.title ?? String(localized: "未知歌曲")),
                "artist": .string(mediaItem.artist ?? String(localized: "未知歌手")),
                "album": .string(mediaItem.albumTitle ?? String(localized: "未知专辑")),
                "duration": .number(mediaItem.playbackDuration)
            ]
            if !mediaItem.playbackStoreID.isEmpty {
                raw["appleMusicStoreID"] = .string(mediaItem.playbackStoreID)
            }
            if let assetURL = mediaItem.assetURL {
                raw["url"] = .string(assetURL.absoluteString)
                raw["localURL"] = .string(assetURL.absoluteString)
            }
            if let image = mediaItem.artwork?.image(at: CGSize(width: 900, height: 900)),
               let data = image.jpegData(compressionQuality: 0.9) {
                let artworkURL = localMusicDirectory.appending(path: "apple-music-\(persistentID)-artwork.jpg")
                if (try? data.write(to: artworkURL, options: .atomic)) != nil {
                    raw["artwork"] = .string(ArtworkURL.persistedReference(for: artworkURL))
                }
            } else if let existingArtwork = existingTracks[persistentID]?.artwork {
                raw["artwork"] = .string(existingArtwork)
            }
            return MusicItem(raw: raw)
        }

        if !imported.isEmpty {
            let target = playlists.first(where: { $0.name == "Apple Music" }) ?? createPlaylist(name: "Apple Music")
            add(imported, to: target)
        }
        return imported
    }

    func exportData() throws -> Data {
        try JSONEncoder.pretty.encode(snapshot)
    }

    func restore(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(LibrarySnapshot.self, from: data)
        favorites = restored.favorites
        playlists = restored.playlists
        history = restored.history
        downloads = restored.downloads.filter {
            fileManager.fileExists(atPath: downloadsDirectory.appending(path: $0.localFilename).path)
        }
        persist()
    }

    private var snapshot: LibrarySnapshot {
        LibrarySnapshot(favorites: favorites, playlists: playlists, history: history, downloads: downloads)
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(LibrarySnapshot.self, from: data) else { return }
        favorites = stored.favorites
        playlists = stored.playlists
        history = stored.history
        downloads = stored.downloads
    }

    private func persist() {
        guard let data = try? JSONEncoder.pretty.encode(snapshot) else { return }
        let destination = libraryURL
        persistenceQueue.async {
            try? data.write(to: destination, options: .atomic)
        }
    }

    private func unique(_ tracks: [MusicItem]) -> [MusicItem] {
        var ids = Set<String>()
        return tracks.filter { ids.insert($0.stableID).inserted }
    }
}

private struct LibrarySnapshot: Codable {
    var favorites: [MusicItem]
    var playlists: [LocalPlaylist]
    var history: [PlaybackHistoryEntry]
    var downloads: [DownloadedTrack]
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .light: String(localized: "浅色")
        case .dark: String(localized: "深色")
        }
    }
}

enum NowPlayingStyle: String, CaseIterable, Identifiable {
    case immersive
    case artwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immersive: String(localized: "沉浸封面")
        case .artwork: String(localized: "氛围唱片")
        }
    }

    var symbol: String {
        switch self {
        case .immersive: "rectangle.portrait.fill"
        case .artwork: "square.stack.fill"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var quality: AudioQuality {
        didSet { defaults.set(quality.rawValue, forKey: "audioQuality") }
    }
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    var nowPlayingStyle: NowPlayingStyle {
        didSet { defaults.set(nowPlayingStyle.rawValue, forKey: "nowPlayingStyle") }
    }
    var playbackRate: Double {
        didSet { defaults.set(playbackRate, forKey: "playbackRate") }
    }
    var continueAfterInterruption: Bool {
        didSet { defaults.set(continueAfterInterruption, forKey: "continueAfterInterruption") }
    }

    private let defaults = UserDefaults.standard

    init() {
        quality = AudioQuality(rawValue: defaults.string(forKey: "audioQuality") ?? "high") ?? .high
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        nowPlayingStyle = NowPlayingStyle(rawValue: defaults.string(forKey: "nowPlayingStyle") ?? "immersive") ?? .immersive
        playbackRate = defaults.object(forKey: "playbackRate") as? Double ?? 1
        continueAfterInterruption = defaults.object(forKey: "continueAfterInterruption") as? Bool ?? true
    }
}
