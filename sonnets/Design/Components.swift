import SwiftUI
import UIKit
import Observation

@MainActor
@Observable
final class PlaybackTheme {
    private(set) var accent = Color(uiColor: .systemBlue)

    func update(for artwork: String?) async {
        let color = await ArtworkImageRepository.shared.accentColor(
            for: artwork,
            fallback: .systemBlue
        )
        guard !Task.isCancelled else { return }
        accent = color
    }
}

enum PlatformBrand {
    static func assetName(for platform: String) -> String? {
        let value = platform.lowercased().replacingOccurrences(of: " ", with: "")
        if value.contains("bilibili") || value.contains("哔哩") || value.contains("b站") {
            return "PlatformBilibili"
        }
        if value.contains("kugou") || value.contains("酷狗") {
            return "PlatformKugou"
        }
        if value.contains("网易") || value.contains("wangyi") || value.contains("netease") {
            return "PlatformNetEase"
        }
        if value.contains("youtube") || value.contains("油管") {
            return "PlatformYouTube"
        }
        return nil
    }
}

struct PlatformBrandMark: View {
    let platform: String
    var size: CGFloat = 20
    var showsFallback = false

    var body: some View {
        if let assetName = PlatformBrand.assetName(for: platform) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else if showsFallback {
            Image(systemName: "music.note.circle.fill")
                .font(.system(size: size * 0.86, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct AppBackground: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
    }
}

struct RemoteArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    var symbol = "music.note"
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeOut(duration: 0.28)))
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.88))
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .task(id: urlString) {
            image = nil
            guard ArtworkURL.resolve(urlString) != nil else {
                isLoading = false
                return
            }
            isLoading = true
            let loadedImage = await ArtworkImageRepository.shared.image(for: urlString)
            guard !Task.isCancelled else { return }
            image = loadedImage
            isLoading = false
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.accentColor.opacity(0.35), .indigo.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

enum ArtworkURL {
    private static let localArtworkScheme = "sonnets-artwork"

    static var localArtworkDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Sonnets", directoryHint: .isDirectory)
            .appending(path: "Local Music", directoryHint: .isDirectory)
    }

    static func persistedReference(for localURL: URL) -> String {
        guard localURL.isFileURL else { return localURL.absoluteString }
        var components = URLComponents()
        components.scheme = localArtworkScheme
        components.host = "local"
        components.path = "/\(localURL.lastPathComponent)"
        return components.string ?? localURL.absoluteString
    }

    static func resolve(_ value: String?) -> URL? {
        guard var value else { return nil }
        value = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("//") {
            value = "https:\(value)"
        } else if !value.contains("://"), !value.hasPrefix("file:") {
            value = "https://\(value)"
        }

        if let url = URL(string: value) {
            if url.scheme == localArtworkScheme {
                return localArtworkDirectory.appending(path: url.lastPathComponent)
            }
            if url.isFileURL,
               !FileManager.default.fileExists(atPath: url.path) {
                let migratedURL = localArtworkDirectory.appending(path: url.lastPathComponent)
                if FileManager.default.fileExists(atPath: migratedURL.path) {
                    return migratedURL
                }
            }
            return url
        }
        return URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
    }
}

@MainActor
final class ArtworkImageRepository {
    static let shared = ArtworkImageRepository()

    private let cache = NSCache<NSURL, UIImage>()
    private let dominantColorCache = NSCache<NSURL, UIColor>()
    private let accentColorCache = NSCache<NSURL, UIColor>()
    private var requests: [URL: Task<UIImage?, Never>] = [:]

    func image(for value: String?) async -> UIImage? {
        guard let url = ArtworkURL.resolve(value) else { return nil }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if url.isFileURL {
            let image = UIImage(contentsOfFile: url.path)
            if let image { cache.setObject(image, forKey: url as NSURL) }
            return image
        }
        if let request = requests[url] {
            return await request.value
        }

        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Sonnets/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            if let scheme = url.scheme, let host = url.host {
                request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }

        requests[url] = task
        let image = await task.value
        requests[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    func dominantColor(for value: String?, fallback: UIColor = .black) async -> Color {
        guard let url = ArtworkURL.resolve(value) else { return Color(uiColor: fallback) }
        if let cached = dominantColorCache.object(forKey: url as NSURL) {
            return Color(uiColor: cached)
        }
        guard let image = await image(for: value) else { return Color(uiColor: fallback) }
        let color = image.artworkDominantColor ?? fallback
        dominantColorCache.setObject(color, forKey: url as NSURL)
        return Color(uiColor: color)
    }

    func accentColor(for value: String?, fallback: UIColor = .systemBlue) async -> Color {
        guard let url = ArtworkURL.resolve(value) else { return Color(uiColor: fallback) }
        if let cached = accentColorCache.object(forKey: url as NSURL) {
            return Color(uiColor: cached)
        }
        guard let image = await image(for: value) else { return Color(uiColor: fallback) }
        let color = (image.artworkDominantColor ?? fallback).readableArtworkAccent
        accentColorCache.setObject(color, forKey: url as NSURL)
        return Color(uiColor: color)
    }
}

private extension UIColor {
    var readableArtworkAccent: UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil) else {
            return self
        }

        let adjustedSaturation = min(max(saturation * 1.12, 0.42), 0.92)
        return UIColor { traits in
            let adjustedBrightness: CGFloat
            if traits.userInterfaceStyle == .dark {
                adjustedBrightness = min(max(brightness * 1.65, 0.72), 0.92)
            } else {
                adjustedBrightness = min(max(brightness, 0.34), 0.48)
            }
            return UIColor(
                hue: hue,
                saturation: adjustedSaturation,
                brightness: adjustedBrightness,
                alpha: 1
            )
        }
    }
}

private extension UIImage {
    var artworkDominantColor: UIColor? {
        guard let cgImage = normalizedCGImage else { return nil }

        let sampleWidth = 36
        let sampleHeight = 36
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        struct Bucket {
            var score = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
            var weight = 0.0
        }

        var buckets: [Int: Bucket] = [:]
        var fallbackRed = 0.0
        var fallbackGreen = 0.0
        var fallbackBlue = 0.0
        var fallbackCount = 0.0

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }

            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let delta = maximum - minimum
            let saturation = maximum == 0 ? 0 : delta / maximum
            let brightness = maximum

            fallbackRed += red
            fallbackGreen += green
            fallbackBlue += blue
            fallbackCount += 1

            guard brightness > 0.07, brightness < 0.96, saturation > 0.08 else { continue }

            let hue: Double
            if delta == 0 {
                hue = 0
            } else if maximum == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
            } else if maximum == green {
                hue = (((blue - red) / delta) + 2) / 6
            } else {
                hue = (((red - green) / delta) + 4) / 6
            }
            let normalizedHue = hue < 0 ? hue + 1 : hue
            let hueBucket = min(Int(normalizedHue * 24), 23)
            let saturationBucket = min(Int(saturation * 4), 3)
            let brightnessBucket = min(Int(brightness * 4), 3)
            let key = hueBucket * 16 + saturationBucket * 4 + brightnessBucket
            let colorWeight = 0.55 + saturation * 1.65
            var bucket = buckets[key, default: Bucket()]
            bucket.score += colorWeight
            bucket.red += red * colorWeight
            bucket.green += green * colorWeight
            bucket.blue += blue * colorWeight
            bucket.weight += colorWeight
            buckets[key] = bucket
        }

        let chosen: (red: Double, green: Double, blue: Double)
        if let bucket = buckets.values.max(by: { $0.score < $1.score }), bucket.weight > 0 {
            chosen = (bucket.red / bucket.weight, bucket.green / bucket.weight, bucket.blue / bucket.weight)
        } else if fallbackCount > 0 {
            chosen = (fallbackRed / fallbackCount, fallbackGreen / fallbackCount, fallbackBlue / fallbackCount)
        } else {
            return nil
        }

        let source = UIColor(red: chosen.red, green: chosen.green, blue: chosen.blue, alpha: 1)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return UIColor(
            hue: hue,
            saturation: min(max(saturation * 1.08, 0.30), 0.92),
            brightness: min(max(brightness * 0.72, 0.20), 0.46),
            alpha: 1
        )
    }

    var normalizedCGImage: CGImage? {
        if let cgImage { return cgImage }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var interactive = false
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct MusicRow: View {
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(PluginManager.self) private var plugins
    @Environment(AppSettings.self) private var settings

    let track: MusicItem
    var tracks: [MusicItem]? = nil
    var showArtwork = true

    var body: some View {
        HStack(spacing: 8) {
            Button {
                player.play(track, in: tracks)
            } label: {
                HStack(spacing: 12) {
                    if showArtwork {
                        RemoteArtwork(urlString: track.artwork, cornerRadius: 9)
                            .frame(width: 48, height: 48)
                            .clipped()
                            .fixedSize()
                            .layoutPriority(2)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.body.weight(player.currentTrack?.stableID == track.stableID ? .semibold : .regular))
                            .foregroundStyle(player.currentTrack?.stableID == track.stableID ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(track.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    if library.isDownloaded(track) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("已下载")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.title)，\(track.artist)")
            .accessibilityHint("轻点播放")

            Menu {
                Button(
                    library.isFavorite(track) ? String(localized: "取消收藏") : String(localized: "收藏"),
                    systemImage: library.isFavorite(track) ? "heart.slash" : "heart"
                ) {
                    library.toggleFavorite(track)
                }
                if !library.playlists.isEmpty {
                    Menu("添加到歌单", systemImage: "text.badge.plus") {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) { library.add([track], to: playlist) }
                        }
                    }
                }
                Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.enqueueNext(track)
                }
                if library.activeDownloads.contains(track.stableID) {
                    Button("正在下载…", systemImage: "arrow.down.circle.dotted") { }
                        .disabled(true)
                } else if !library.isDownloaded(track) {
                    Button("下载", systemImage: "arrow.down.circle") {
                        Task {
                            await library.download(track, using: plugins, quality: settings.quality)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 34, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多操作")
        }
        .frame(minHeight: showArtwork ? 56 : 44)
    }
}

struct MiniPlayer: View {
    @Environment(PlayerService.self) private var player
    @Environment(PlaybackTheme.self) private var playbackTheme
    let onOpen: () -> Void
    var embeddedInTabBar = false
    var compact = false

    var body: some View {
        if let track = player.currentTrack {
            playerSurface(track)
                .overlay(alignment: .bottom) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(playbackTheme.accent)
                            .frame(width: geometry.size.width * min(max(player.progress / max(player.duration, 1), 0), 1), height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, embeddedInTabBar ? 8 : 18)
                }
                .padding(.horizontal, embeddedInTabBar ? 0 : 10)
        }
    }

    @ViewBuilder
    private func playerSurface(_ track: MusicItem) -> some View {
        if embeddedInTabBar {
            playerContent(track)
        } else {
            GlassSurface(cornerRadius: 999, interactive: true) {
                playerContent(track)
            }
        }
    }

    private func playerContent(_ track: MusicItem) -> some View {
        let artworkSize: CGFloat = compact ? 36 : (embeddedInTabBar ? 44 : 44)
        let controlSize: CGFloat = compact ? 38 : 38
        let horizontalInset: CGFloat = compact ? 5 : (embeddedInTabBar ? 6 : 7)
        let verticalInset: CGFloat = compact ? 4 : (embeddedInTabBar ? 5 : 6)
        return HStack(spacing: compact ? 8 : 10) {
            Button(action: openNowPlaying) {
                HStack(spacing: compact ? 7 : 10) {
                    RemoteArtwork(urlString: track.artwork, cornerRadius: artworkSize * 0.5)
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.16), lineWidth: 0.7)
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(track.artist)
                            .font(compact ? .caption2 : .caption)
                            .foregroundStyle(playbackTheme.accent)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开正在播放：\(track.title)，\(track.artist)")

            if player.isLoading {
                ProgressView().controlSize(.small).frame(width: controlSize, height: controlSize)
            } else {
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(compact ? .body : .title3)
                        .frame(width: controlSize, height: controlSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            }
            if !compact {
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").frame(width: 34, height: controlSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }
        }
        .padding(.leading, horizontalInset)
        .padding(.trailing, horizontalInset + (compact ? 3 : 4))
        .padding(.vertical, verticalInset)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 48 : (embeddedInTabBar ? 56 : 56))
        .contentShape(.capsule)
    }

    private func openNowPlaying() {
        onOpen()
    }
}

@available(iOS 26.0, *)
struct TabAccessoryMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let onOpen: () -> Void

    var body: some View {
        MiniPlayer(
            onOpen: onOpen,
            embeddedInTabBar: true,
            compact: placement == .inline
        )
        .animation(.smooth(duration: 0.38), value: placement == .inline)
    }
}

struct EmptyContentView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

extension TimeInterval {
    var playbackTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
