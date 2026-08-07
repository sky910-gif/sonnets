import Foundation
import Observation

struct InstalledPlugin: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var manifest: PluginManifest
    var sourceURL: String?
    var localFilename: String
    var enabled: Bool
    var installedAt: Date
    var userVariables: [String: String]
    var customName: String? = nil

    var name: String {
        let value = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? manifest.platform : value
    }
    var platformIdentifier: String { manifest.platform }
}

struct PluginSubscription: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var url: String
    var title: String
    var updatedAt: Date
}

@MainActor
@Observable
final class PluginManager {
    static let defaultSourceURL = "https://musicfreepluginshub.2020818.xyz/plugins.json"

    private(set) var plugins: [InstalledPlugin] = []
    private(set) var subscriptions: [PluginSubscription] = []
    private(set) var isWorking = false
    private(set) var statusMessage = ""
    var lastError: String?
    var selectedPluginID: UUID? {
        didSet {
            if let selectedPluginID {
                UserDefaults.standard.set(selectedPluginID.uuidString, forKey: "selectedPluginID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPluginID")
            }
        }
    }

    private var runtimes: [UUID: PluginRuntime] = [:]
    private let fileManager = FileManager.default

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appending(path: "Sonnets", directoryHint: .isDirectory)
    }

    private var pluginsDirectory: URL { rootDirectory.appending(path: "Plugins", directoryHint: .isDirectory) }
    private var catalogURL: URL { rootDirectory.appending(path: "plugins.json") }
    private var subscriptionsURL: URL { rootDirectory.appending(path: "subscriptions.json") }

    init() {
        createDirectories()
        loadPersistedState()
        let savedID = UserDefaults.standard.string(forKey: "selectedPluginID").flatMap(UUID.init(uuidString:))
        selectedPluginID = plugins.first(where: { $0.id == savedID && $0.enabled })?.id ?? plugins.first(where: \.enabled)?.id
    }

    var enabledPlugins: [InstalledPlugin] { plugins.filter(\.enabled) }

    func bootstrap() async {
        guard plugins.isEmpty, !isWorking else { return }
        do {
            try await importSource(Self.defaultSourceURL, title: String(localized: "MusicFree 插件中心"))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importSource(_ rawURL: String, title: String? = nil) async throws {
        guard let url = normalizedURL(rawURL) else { throw URLError(.badURL) }
        isWorking = true
        statusMessage = String(localized: "正在读取插件源…")
        lastError = nil
        defer {
            isWorking = false
            statusMessage = ""
        }

        let data = try await download(url)
        if url.pathExtension.lowercased() == "js" || looksLikeJavaScript(data) {
            _ = try await installPlugin(code: String(decoding: data, as: UTF8.self), sourceURL: url)
            return
        }

        let descriptors = try parseSource(data: data, baseURL: url)
        guard !descriptors.isEmpty else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "订阅中没有可安装的插件"))
        }

        var installedCount = 0
        var failures: [String] = []
        for (index, descriptor) in descriptors.enumerated() {
            statusMessage = String(
                format: String(localized: "正在安装 %@（%d/%d）"),
                descriptor.name ?? String(localized: "插件"),
                index + 1,
                descriptors.count
            )
            do {
                let codeData = try await download(descriptor.url)
                _ = try await installPlugin(code: String(decoding: codeData, as: UTF8.self), sourceURL: descriptor.url)
                installedCount += 1
            } catch {
                failures.append("\(descriptor.name ?? descriptor.url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        let subscription = PluginSubscription(
            id: subscriptions.first(where: { $0.url == url.absoluteString })?.id ?? UUID(),
            url: url.absoluteString,
            title: title ?? url.host() ?? "网络插件源",
            updatedAt: .now
        )
        subscriptions.removeAll { $0.url == subscription.url }
        subscriptions.append(subscription)
        persistSubscriptions()

        if installedCount == 0 {
            throw PluginRuntimeError.invalidPlugin(failures.joined(separator: "\n"))
        }
        if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
        selectedPluginID = selectedPluginID ?? enabledPlugins.first?.id
    }

    @discardableResult
    func installPlugin(code: String, sourceURL: URL?) async throws -> InstalledPlugin {
        let runtime = PluginRuntime(code: code, sourceURL: sourceURL)
        let manifest = try await runtime.prepare()
        let existing = plugins.first { $0.platformIdentifier == manifest.platform }
        let id = existing?.id ?? UUID()
        let filename = existing?.localFilename ?? "\(id.uuidString).js"
        let fileURL = pluginsDirectory.appending(path: filename)
        try Data(code.utf8).write(to: fileURL, options: .atomic)

        let plugin = InstalledPlugin(
            id: id,
            manifest: manifest,
            sourceURL: sourceURL?.absoluteString ?? manifest.sourceURL,
            localFilename: filename,
            enabled: existing?.enabled ?? true,
            installedAt: .now,
            userVariables: existing?.userVariables ?? [:],
            customName: existing?.customName
        )
        if let index = plugins.firstIndex(where: { $0.id == id || $0.platformIdentifier == manifest.platform }) {
            plugins[index] = plugin
        } else {
            plugins.append(plugin)
        }
        runtimes[id] = runtime
        persistPlugins()
        selectedPluginID = selectedPluginID ?? id
        return plugin
    }

    func update(_ plugin: InstalledPlugin) async throws {
        guard let source = plugin.sourceURL, let url = URL(string: source) else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "插件没有更新地址"))
        }
        isWorking = true
        statusMessage = String(
            format: String(localized: "正在更新 %@…"),
            plugin.name
        )
        defer { isWorking = false; statusMessage = "" }
        let data = try await download(url)
        _ = try await installPlugin(code: String(decoding: data, as: UTF8.self), sourceURL: url)
    }

    func refreshSubscriptions() async {
        for subscription in subscriptions {
            do {
                try await importSource(subscription.url, title: subscription.title)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setEnabled(_ plugin: InstalledPlugin, enabled: Bool) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[index].enabled = enabled
        if !enabled, selectedPluginID == plugin.id { selectedPluginID = enabledPlugins.first?.id }
        persistPlugins()
    }

    func movePlugins(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { plugins[$0] }
        for index in offsets.sorted(by: >) { plugins.remove(at: index) }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count
        let adjustedDestination = max(0, min(destination - removedBeforeDestination, plugins.count))
        plugins.insert(contentsOf: moving, at: adjustedDestination)
        persistPlugins()
    }

    func rename(_ plugin: InstalledPlugin, to name: String) {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        plugins[index].customName = trimmed.isEmpty || trimmed == plugin.platformIdentifier ? nil : trimmed
        persistPlugins()
    }

    func setUserVariables(_ values: [String: String], for plugin: InstalledPlugin) async throws {
        guard let index = plugins.firstIndex(where: { $0.id == plugin.id }) else { return }
        plugins[index].userVariables = values
        runtimes[plugin.id] = nil
        _ = try await runtime(for: plugins[index])
        persistPlugins()
    }

    func remove(_ plugin: InstalledPlugin) {
        try? fileManager.removeItem(at: pluginsDirectory.appending(path: plugin.localFilename))
        plugins.removeAll { $0.id == plugin.id }
        runtimes[plugin.id] = nil
        if selectedPluginID == plugin.id { selectedPluginID = enabledPlugins.first?.id }
        persistPlugins()
    }

    func search(query: String, page: Int = 1, type: MediaType = .music, pluginID: UUID? = nil) async throws -> [SearchResultItem] {
        let targets: [InstalledPlugin]
        if let pluginID, let plugin = enabledPlugins.first(where: { $0.id == pluginID }) {
            targets = [plugin]
        } else {
            targets = enabledPlugins.filter { $0.manifest.supportedSearchTypes.contains(type) }
        }
        guard !targets.isEmpty else {
            throw PluginRuntimeError.invalidPlugin(
                String(localized: "请先安装并启用支持该类型的插件")
            )
        }

        var output: [SearchResultItem] = []
        var firstError: Error?
        for plugin in targets {
            do {
                let value = try await runtime(for: plugin).invoke(
                    "search",
                    arguments: [.string(query), .number(Double(page)), .string(type.rawValue)]
                )
                let data = searchPayload(from: value)
                output.append(contentsOf: data.compactMap { searchResult(from: $0, type: type, platform: plugin.name) })
            } catch {
                firstError = firstError ?? error
            }
        }
        if output.isEmpty, let firstError { throw firstError }
        return deduplicated(output)
    }

    func mediaSource(for item: MusicItem, quality: AudioQuality) async throws -> MediaSource {
        guard let plugin = plugin(matching: item.platform) else {
            if let urlString = directURL(for: item, quality: quality), let url = URL(string: urlString) {
                return MediaSource(url: url, headers: [:], quality: quality)
            }
            throw PluginRuntimeError.invalidPlugin(
                String(format: String(localized: "找不到歌曲对应的插件：%@"), item.platform)
            )
        }

        if plugin.manifest.supportedMethods.contains("getMediaSource") {
            let result = try await runtime(for: plugin).invoke(
                "getMediaSource",
                arguments: [.object(item.raw), .string(quality.rawValue)]
            )
            if let object = result.objectValue,
               let urlString = object.string("url"),
               let url = URL(string: urlString) {
                let headers = object["headers"]?.objectValue?.reduce(into: [String: String]()) { result, entry in
                    if let value = entry.value.stringValue { result[entry.key] = value }
                } ?? [:]
                return MediaSource(url: url, headers: headers, quality: quality)
            }
        }
        if let urlString = directURL(for: item, quality: quality), let url = URL(string: urlString) {
            return MediaSource(url: url, headers: [:], quality: quality)
        }
        throw PluginRuntimeError.invalidResponse
    }

    func musicInfo(for item: MusicItem) async -> MusicItem {
        guard let plugin = plugin(matching: item.platform),
              plugin.manifest.supportedMethods.contains("getMusicInfo"),
              let result = try? await runtime(for: plugin).invoke("getMusicInfo", arguments: [.object(item.raw)]),
              let details = result.objectValue else { return item }
        var enriched = item
        enriched.merge(details)
        return enriched
    }

    func lyrics(for item: MusicItem) async throws -> LyricSource {
        if let raw = item.raw.string("rawLrc"), !raw.isEmpty {
            return LyricSource(raw: ["rawLrc": .string(raw)])
        }
        if let plugin = plugin(matching: item.platform),
           plugin.manifest.supportedMethods.contains("getLyric") {
            let result = try await runtime(for: plugin).invoke("getLyric", arguments: [.object(item.raw)])
            if let object = result.objectValue { return LyricSource(raw: object) }
        }
        if let lyricURLString = item.raw.string("lrc"), let lyricURL = URL(string: lyricURLString) {
            let data = try await download(lyricURL)
            return LyricSource(raw: ["rawLrc": .string(String(decoding: data, as: UTF8.self))])
        }
        throw PluginRuntimeError.invalidResponse
    }

    func supportsComments(for item: MusicItem) -> Bool {
        plugin(matching: item.platform)?.manifest.supportedMethods.contains("getMusicComments") == true
    }

    func comments(for item: MusicItem, page: Int = 1) async throws -> MusicCommentPage {
        let plugin = try plugin(named: item.platform, method: "getMusicComments")
        let result = try await runtime(for: plugin).invoke(
            "getMusicComments",
            arguments: [.object(item.raw), .number(Double(page))],
            timeout: 30
        )
        guard let object = result.objectValue else { throw PluginRuntimeError.invalidResponse }
        let values = object["data"]?.arrayValue ?? object["comments"]?.arrayValue ?? []
        let comments = values.compactMap { value in
            value.objectValue.map(MusicComment.init(raw:))
        }
        return MusicCommentPage(comments: comments, isEnd: object["isEnd"]?.boolValue ?? comments.isEmpty)
    }

    func albumDetails(_ album: AlbumItem, page: Int = 1) async throws -> (AlbumItem, [MusicItem], Bool) {
        let plugin = try plugin(named: album.platform, method: "getAlbumInfo")
        let result = try await runtime(for: plugin).invoke("getAlbumInfo", arguments: [.object(album.raw), .number(Double(page))])
        guard let object = result.objectValue else { throw PluginRuntimeError.invalidResponse }
        let updated = AlbumItem(raw: object["albumItem"]?.objectValue ?? album.raw, platform: plugin.name)
        let tracks = musicItems(object["musicList"], platform: plugin.name)
        return (updated, tracks, object["isEnd"]?.boolValue ?? true)
    }

    func playlistDetails(_ playlist: RemotePlaylistItem, page: Int = 1) async throws -> (RemotePlaylistItem, [MusicItem], Bool) {
        let plugin = try plugin(named: playlist.platform, method: "getMusicSheetInfo")
        let result = try await runtime(for: plugin).invoke("getMusicSheetInfo", arguments: [.object(playlist.raw), .number(Double(page))])
        guard let object = result.objectValue else { throw PluginRuntimeError.invalidResponse }
        let updated = RemotePlaylistItem(raw: object["sheetItem"]?.objectValue ?? playlist.raw, platform: plugin.name)
        let tracks = musicItems(object["musicList"], platform: plugin.name)
        return (updated, tracks, object["isEnd"]?.boolValue ?? true)
    }

    func artistWorks(_ artist: ArtistItem, page: Int = 1, type: MediaType = .music) async throws -> [SearchResultItem] {
        let plugin = try plugin(named: artist.platform, method: "getArtistWorks")
        let result = try await runtime(for: plugin).invoke(
            "getArtistWorks",
            arguments: [.object(artist.raw), .number(Double(page)), .string(type.rawValue)]
        )
        return (result.objectValue?["data"]?.arrayValue ?? []).compactMap {
            searchResult(from: $0, type: type, platform: plugin.name)
        }
    }

    func importPlaylist(_ text: String, using pluginID: UUID) async throws -> [MusicItem] {
        guard let plugin = enabledPlugins.first(where: { $0.id == pluginID }) else {
            throw PluginRuntimeError.invalidPlugin(String(localized: "未选择插件"))
        }
        let value = try await runtime(for: plugin).invoke("importMusicSheet", arguments: [.string(text)], timeout: 60)
        return musicItems(value, platform: plugin.name)
    }

    func importPlaylistAutomatically(_ text: String) async throws -> [MusicItem] {
        let candidates = enabledPlugins.filter { $0.manifest.supportedMethods.contains("importMusicSheet") }
        guard !candidates.isEmpty else {
            throw PluginRuntimeError.invalidPlugin(
                String(localized: "没有已启用且支持歌单导入的插件")
            )
        }

        var failures: [String] = []
        for plugin in candidates {
            do {
                let tracks = try await importPlaylist(text, using: plugin.id)
                if !tracks.isEmpty { return tracks }
            } catch {
                failures.append("\(plugin.name)：\(error.localizedDescription)")
            }
        }
        throw PluginRuntimeError.invalidPlugin(failures.joined(separator: "\n"))
    }

    func topLists(using pluginID: UUID) async throws -> [TopListGroup] {
        guard let plugin = enabledPlugins.first(where: { $0.id == pluginID }) else { return [] }
        let result = try await runtime(for: plugin).invoke("getTopLists", arguments: [])
        return (result.arrayValue ?? []).enumerated().compactMap { index, value in
            guard let object = value.objectValue else { return nil }
            let title = object.string("title", "name") ?? "榜单"
            let lists = (object["data"]?.arrayValue ?? []).compactMap { value -> RemotePlaylistItem? in
                guard let raw = value.objectValue else { return nil }
                return RemotePlaylistItem(raw: raw, platform: plugin.name)
            }
            return TopListGroup(id: "\(plugin.id)-\(index)-\(title)", title: title, playlists: lists)
        }
    }

    func topListDetails(_ playlist: RemotePlaylistItem) async throws -> [MusicItem] {
        let plugin = try plugin(named: playlist.platform, method: "getTopListDetail")
        let result = try await runtime(for: plugin).invoke(
            "getTopListDetail",
            arguments: [.object(playlist.raw), .number(1)],
            timeout: 30
        )
        return musicItems(result.objectValue?["musicList"], platform: plugin.name)
    }

    func recommendTags(using pluginID: UUID) async throws -> (pinned: [PlaylistTag], groups: [PlaylistTagGroup]) {
        guard let plugin = enabledPlugins.first(where: { $0.id == pluginID }) else { return ([], []) }
        let result = try await runtime(for: plugin).invoke("getRecommendSheetTags", arguments: [])
        guard let object = result.objectValue else { throw PluginRuntimeError.invalidResponse }
        let pinned = (object["pinned"]?.arrayValue ?? []).compactMap { value -> PlaylistTag? in
            guard let raw = value.objectValue else { return nil }
            return PlaylistTag(raw: raw)
        }
        let groups = (object["data"]?.arrayValue ?? []).enumerated().compactMap { index, value -> PlaylistTagGroup? in
            guard let raw = value.objectValue else { return nil }
            let title = raw.string("title", "name") ?? "分类"
            let tags = (raw["data"]?.arrayValue ?? []).compactMap { value -> PlaylistTag? in
                guard let tag = value.objectValue else { return nil }
                return PlaylistTag(raw: tag)
            }
            return PlaylistTagGroup(id: "\(plugin.id)-\(index)-\(title)", title: title, tags: tags)
        }
        return (pinned, groups)
    }

    func recommendPlaylists(using pluginID: UUID, tag: PlaylistTag, page: Int = 1) async throws -> [RemotePlaylistItem] {
        guard let plugin = enabledPlugins.first(where: { $0.id == pluginID }) else { return [] }
        let result = try await runtime(for: plugin).invoke(
            "getRecommendSheetsByTag",
            arguments: [.object(tag.raw), .number(Double(page))]
        )
        return (result.objectValue?["data"]?.arrayValue ?? []).compactMap { value in
            guard let raw = value.objectValue else { return nil }
            return RemotePlaylistItem(raw: raw, platform: plugin.name)
        }
    }

    private func runtime(for plugin: InstalledPlugin) async throws -> PluginRuntime {
        if let runtime = runtimes[plugin.id] { return runtime }
        let fileURL = pluginsDirectory.appending(path: plugin.localFilename)
        let code = try String(contentsOf: fileURL, encoding: .utf8)
        let runtime = PluginRuntime(code: code, sourceURL: plugin.sourceURL.flatMap(URL.init(string:)))
        _ = try await runtime.prepare(userVariables: plugin.userVariables)
        runtimes[plugin.id] = runtime
        return runtime
    }

    private func plugin(named name: String, method: String) throws -> InstalledPlugin {
        guard let plugin = enabledPlugins.first(where: { $0.name == name || $0.platformIdentifier == name }) else {
            throw PluginRuntimeError.invalidPlugin(
                String(format: String(localized: "找不到或未启用 %@"), name)
            )
        }
        guard plugin.manifest.supportedMethods.contains(method) else {
            throw PluginRuntimeError.unsupportedMethod(method)
        }
        return plugin
    }

    private func plugin(matching name: String) -> InstalledPlugin? {
        plugins.first { $0.name == name || $0.platformIdentifier == name }
    }

    private func searchResult(from value: JSONValue, type: MediaType, platform: String) -> SearchResultItem? {
        guard let raw = value.objectValue else { return nil }
        switch type {
        case .music: return .music(MusicItem(raw: raw, platform: platform))
        case .album: return .album(AlbumItem(raw: raw, platform: platform))
        case .artist: return .artist(ArtistItem(raw: raw, platform: platform))
        case .sheet: return .sheet(RemotePlaylistItem(raw: raw, platform: platform))
        case .lyric:
            return .lyric(LyricSearchItem(music: MusicItem(raw: raw, platform: platform)))
        }
    }

    private func searchPayload(from value: JSONValue) -> [JSONValue] {
        if let values = value.arrayValue { return values }
        guard let object = value.objectValue else { return [] }

        for key in ["data", "results", "items", "list"] {
            guard let candidate = object[key] else { continue }
            if let values = candidate.arrayValue { return values }
            if let nested = candidate.objectValue {
                for nestedKey in ["data", "results", "items", "list"] {
                    if let values = nested[nestedKey]?.arrayValue { return values }
                }
            }
        }
        return []
    }

    private func musicItems(_ value: JSONValue?, platform: String) -> [MusicItem] {
        (value?.arrayValue ?? []).compactMap { value in
            guard let raw = value.objectValue else { return nil }
            return MusicItem(raw: raw, platform: platform)
        }
    }

    private func directURL(for item: MusicItem, quality: AudioQuality) -> String? {
        if let qualities = item.raw["qualities"]?.objectValue,
           let qualityObject = qualities[quality.rawValue]?.objectValue,
           let qualityURL = qualityObject.string("url") {
            return qualityURL
        }
        return item.directURL
    }

    private func deduplicated(_ values: [SearchResultItem]) -> [SearchResultItem] {
        var ids = Set<String>()
        return values.filter { ids.insert($0.id).inserted }
    }

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Sonnets/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    private func looksLikeJavaScript(_ data: Data) -> Bool {
        let prefix = String(decoding: data.prefix(300), as: UTF8.self)
        return prefix.contains("module.exports") || prefix.contains("Object.defineProperty(exports")
    }

    private func parseSource(data: Data, baseURL: URL) throws -> [PluginSourceDescriptor] {
        let object = try JSONSerialization.jsonObject(with: data)
        let array: [[String: Any]]
        if let root = object as? [String: Any] {
            array = (root["plugins"] ?? root["data"]) as? [[String: Any]] ?? []
        } else {
            array = object as? [[String: Any]] ?? []
        }
        return array.compactMap { object in
            guard let rawURL = (object["url"] ?? object["srcUrl"] ?? object["source"]) as? String,
                  let url = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL else { return nil }
            return PluginSourceDescriptor(name: object["name"] as? String, url: url)
        }
    }

    private func createDirectories() {
        try? fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
    }

    private func loadPersistedState() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: catalogURL), let decoded = try? decoder.decode([InstalledPlugin].self, from: data) {
            plugins = decoded.filter { fileManager.fileExists(atPath: pluginsDirectory.appending(path: $0.localFilename).path) }
        }
        if let data = try? Data(contentsOf: subscriptionsURL), let decoded = try? decoder.decode([PluginSubscription].self, from: data) {
            subscriptions = decoded
        }
    }

    private func persistPlugins() {
        guard let data = try? JSONEncoder.pretty.encode(plugins) else { return }
        try? data.write(to: catalogURL, options: .atomic)
    }

    private func persistSubscriptions() {
        guard let data = try? JSONEncoder.pretty.encode(subscriptions) else { return }
        try? data.write(to: subscriptionsURL, options: .atomic)
    }
}

private struct PluginSourceDescriptor {
    var name: String?
    var url: URL
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
