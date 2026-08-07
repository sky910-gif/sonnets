import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.rounded() == value ? String(format: "%.0f", value) : String(value)
        case .bool(let value): return String(value)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value): return ["true", "1", "yes"].contains(value.lowercased())
        default: return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }

    func number(_ keys: String...) -> Double? {
        for key in keys {
            if let value = self[key]?.doubleValue { return value }
        }
        return nil
    }

    func artworkURL(_ keys: String...) -> String? {
        for key in keys {
            if let direct = self[key]?.stringValue, !direct.isEmpty {
                return direct
            }
        }

        let nestedKeys = [
            "artwork", "artworkUrl", "cover", "coverImg", "coverUrl",
            "pic", "picUrl", "image", "imageUrl", "img", "imgurl", "albumPic"
        ]
        for containerKey in ["album", "albumInfo", "coverInfo", "imageInfo"] {
            guard let object = self[containerKey]?.objectValue else { continue }
            for key in nestedKeys {
                if let nested = object[key]?.stringValue, !nested.isEmpty {
                    return nested
                }
            }
        }
        return nil
    }
}

extension String {
    var musicFreePlainText: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MediaType: String, Codable, CaseIterable, Identifiable, Sendable {
    case music
    case album
    case artist
    case sheet
    case lyric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: String(localized: "歌曲")
        case .album: String(localized: "专辑")
        case .artist: String(localized: "歌手")
        case .sheet: String(localized: "歌单")
        case .lyric: String(localized: "歌词")
        }
    }
}

enum AudioQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case standard
    case high
    case superQuality = "super"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: String(localized: "流畅")
        case .standard: String(localized: "标准")
        case .high: String(localized: "高品质")
        case .superQuality: String(localized: "无损/超高")
        }
    }
}

struct MusicItem: Codable, Hashable, Identifiable, Sendable {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue], platform: String? = nil) {
        var normalized = raw
        if let platform, normalized["platform"]?.stringValue?.isEmpty != false {
            normalized["platform"] = .string(platform)
        }
        self.raw = normalized
    }

    var id: String { raw.string("id", "songmid", "hash") ?? "\(title)::\(artist)::\(album)" }
    var platform: String { raw.string("platform") ?? String(localized: "本地音乐") }
    var title: String { (raw.string("title", "name", "songname") ?? String(localized: "未知歌曲")).musicFreePlainText }
    var artist: String { (raw.string("artist", "singer", "author") ?? String(localized: "未知歌手")).musicFreePlainText }
    var album: String { (raw.string("album", "albumName") ?? String(localized: "未知专辑")).musicFreePlainText }
    var artwork: String? {
        raw.artworkURL(
            "artwork", "artworkUrl", "coverImg", "cover", "coverUrl",
            "picUrl", "pic", "albumPic", "image", "imageUrl", "img", "imgurl"
        )
    }
    var duration: TimeInterval {
        let value = raw.number("duration", "interval") ?? 0
        return value > 86_400 ? value / 1_000 : value
    }
    var directURL: String? { raw.string("url") }
    var subtitle: String {
        [artist, album]
            .filter { !$0.isEmpty && $0 != String(localized: "未知专辑") }
            .joined(separator: " · ")
    }
    var stableID: String { "\(platform)::\(id)" }

    mutating func merge(_ values: [String: JSONValue]) {
        raw.merge(values, uniquingKeysWith: { _, new in new })
    }
}

struct AlbumItem: Codable, Hashable, Identifiable, Sendable {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue], platform: String? = nil) {
        var normalized = raw
        if let platform { normalized["platform"] = normalized["platform"] ?? .string(platform) }
        self.raw = normalized
    }

    var id: String { raw.string("id", "albumid", "albumMID") ?? "\(title)::\(artist)" }
    var platform: String { raw.string("platform") ?? "" }
    var title: String { (raw.string("title", "albumName", "name") ?? String(localized: "未知专辑")).musicFreePlainText }
    var artist: String { (raw.string("artist", "singerName") ?? String(localized: "未知歌手")).musicFreePlainText }
    var artwork: String? {
        raw.artworkURL(
            "artwork", "artworkUrl", "coverImg", "cover", "coverUrl",
            "albumPic", "picUrl", "pic", "image", "imageUrl", "img", "imgurl"
        )
    }
    var description: String { (raw.string("description", "desc") ?? "").musicFreePlainText }
    var stableID: String { "\(platform)::album::\(id)" }
}

struct ArtistItem: Codable, Hashable, Identifiable, Sendable {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue], platform: String? = nil) {
        var normalized = raw
        if let platform { normalized["platform"] = normalized["platform"] ?? .string(platform) }
        self.raw = normalized
    }

    var id: String { raw.string("id", "singerID", "singerMID") ?? name }
    var platform: String { raw.string("platform") ?? "" }
    var name: String { (raw.string("name", "artist", "singerName") ?? String(localized: "未知歌手")).musicFreePlainText }
    var avatar: String? {
        raw.artworkURL(
            "avatar", "avatarUrl", "artwork", "artworkUrl", "singerPic",
            "picUrl", "pic", "image", "imageUrl", "img", "imgurl"
        )
    }
    var description: String { (raw.string("description", "desc") ?? "").musicFreePlainText }
    var stableID: String { "\(platform)::artist::\(id)" }
}

struct RemotePlaylistItem: Codable, Hashable, Identifiable, Sendable {
    var raw: [String: JSONValue]

    init(raw: [String: JSONValue], platform: String? = nil) {
        var normalized = raw
        if let platform { normalized["platform"] = normalized["platform"] ?? .string(platform) }
        self.raw = normalized
    }

    var id: String { raw.string("id", "dissid", "playlistId") ?? "\(title)::\(artist)" }
    var platform: String { raw.string("platform") ?? "" }
    var title: String { (raw.string("title", "name", "dissname") ?? String(localized: "未知歌单")).musicFreePlainText }
    var artist: String { (raw.string("artist", "creator") ?? "").musicFreePlainText }
    var artwork: String? {
        raw.artworkURL(
            "artwork", "artworkUrl", "coverImg", "cover", "coverUrl",
            "imgurl", "img", "image", "imageUrl", "pic", "picUrl"
        )
    }
    var description: String { (raw.string("description", "intro") ?? "").musicFreePlainText }
    var worksCount: Int { Int(raw.number("worksNum", "worksNums", "songCount") ?? 0) }
    var stableID: String { "\(platform)::sheet::\(id)" }
}

struct LyricSearchItem: Codable, Hashable, Identifiable, Sendable {
    var music: MusicItem
    var id: String { music.stableID }
    var preview: String { music.raw.string("rawLrcTxt") ?? "" }
}

enum SearchResultItem: Hashable, Identifiable, Sendable {
    case music(MusicItem)
    case album(AlbumItem)
    case artist(ArtistItem)
    case sheet(RemotePlaylistItem)
    case lyric(LyricSearchItem)

    var id: String {
        switch self {
        case .music(let item): item.stableID
        case .album(let item): item.stableID
        case .artist(let item): item.stableID
        case .sheet(let item): item.stableID
        case .lyric(let item): "lyric::\(item.id)"
        }
    }
}

struct MediaSource: Codable, Hashable, Sendable {
    var url: URL
    var headers: [String: String]
    var quality: AudioQuality?
}

struct LyricSource: Codable, Hashable, Sendable {
    var rawLyric: String?
    var translation: String?

    init(raw: [String: JSONValue]) {
        rawLyric = raw.string("rawLrc", "lyric")
        translation = raw.string("translation", "trans")
    }
}

struct TimedLyricLine: Identifiable, Hashable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
    let translation: String?
}

struct MusicComment: Identifiable, Hashable, Sendable {
    var raw: [String: JSONValue]
    var replies: [MusicComment]

    init(raw: [String: JSONValue]) {
        self.raw = raw
        var parsedReplies: [MusicComment] = []
        for value in raw["replies"]?.arrayValue ?? [] {
            if let object = value.objectValue {
                parsedReplies.append(MusicComment(raw: object))
            }
        }
        replies = parsedReplies
    }

    var id: String {
        raw.string("id", "commentId", "commentID") ?? "\(nickname)::\(content)::\(createdAt?.timeIntervalSince1970 ?? 0)"
    }

    var nickname: String {
        (raw.string("nickName", "nickname", "userName", "name") ?? String(localized: "匿名用户")).musicFreePlainText
    }

    var avatar: String? { raw.string("avatar", "avatarUrl", "userAvatar") }
    var content: String { (raw.string("comment", "content", "text") ?? "").musicFreePlainText }
    var likes: Int { Int(raw.number("like", "likedCount", "likeCount") ?? 0) }
    var location: String { (raw.string("location", "ipLocation") ?? "").musicFreePlainText }

    var createdAt: Date? {
        if let value = raw.number("createAt", "createdAt", "time", "timestamp") {
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
        }
        guard let value = raw.string("createAt", "createdAt", "time") else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

struct MusicCommentPage: Sendable {
    var comments: [MusicComment]
    var isEnd: Bool
}

enum LyricParser {
    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?\]"#)

    static func parse(_ source: LyricSource) -> [TimedLyricLine] {
        let translations = parseText(source.translation ?? "").reduce(into: [Int: String]()) { result, item in
            result[Int(item.time * 100)] = item.text
        }
        return parseText(source.rawLyric ?? "").enumerated().map { index, item in
            TimedLyricLine(
                id: index,
                time: item.time,
                text: item.text,
                translation: translations[Int(item.time * 100)]
            )
        }
    }

    private static func parseText(_ text: String) -> [(time: TimeInterval, text: String)] {
        var lines: [(TimeInterval, String)] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            let matches = timestamp.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }
            let lyricText = timestamp.stringByReplacingMatches(in: rawLine, range: range, withTemplate: "").trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: rawLine),
                    let secondRange = Range(match.range(at: 2), in: rawLine)
                else { continue }
                let minutes = Double(rawLine[minuteRange]) ?? 0
                let seconds = Double(rawLine[secondRange]) ?? 0
                var fraction = 0.0
                if let fractionRange = Range(match.range(at: 3), in: rawLine) {
                    let value = String(rawLine[fractionRange])
                    fraction = (Double(value) ?? 0) / pow(10, Double(value.count))
                }
                lines.append((minutes * 60 + seconds + fraction, lyricText))
            }
        }
        return lines.sorted { $0.0 < $1.0 }
    }
}

struct LocalPlaylist: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var artwork: String?
    var createdAt: Date
    var tracks: [MusicItem]

    init(id: UUID = UUID(), name: String, artwork: String? = nil, createdAt: Date = .now, tracks: [MusicItem] = []) {
        self.id = id
        self.name = name
        self.artwork = artwork
        self.createdAt = createdAt
        self.tracks = tracks
    }
}

struct PlaybackHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    var track: MusicItem
    var playedAt: Date
    var id: String { "\(track.stableID)::\(playedAt.timeIntervalSince1970)" }
}

struct TopListGroup: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var playlists: [RemotePlaylistItem]
}

struct PlaylistTag: Identifiable, Hashable, Sendable {
    var raw: [String: JSONValue]
    var id: String { raw.string("id", "value", "title") ?? "all" }
    var title: String { raw.string("title", "name", "label") ?? String(localized: "推荐") }
}

struct PlaylistTagGroup: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var tags: [PlaylistTag]
}
