import AVFoundation
import MediaPlayer
import Observation
import SwiftUI
import UIKit

enum PlaybackMode: String, CaseIterable, Identifiable, Sendable {
    case sequential
    case repeatAll
    case repeatOne
    case shuffle

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sequential: "arrow.right"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    var title: String {
        switch self {
        case .sequential: String(localized: "顺序播放")
        case .repeatAll: String(localized: "列表循环")
        case .repeatOne: String(localized: "单曲循环")
        case .shuffle: String(localized: "随机播放")
        }
    }
}

@MainActor
@Observable
final class PlayerService {
    private(set) var queue: [MusicItem] = []
    private(set) var currentIndex: Int?
    private(set) var currentTrack: MusicItem?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var lyrics: [TimedLyricLine] = []
    private(set) var lyricSource: LyricSource?
    private(set) var playbackMode: PlaybackMode = .sequential
    private(set) var equalizerEnabled = false
    private(set) var equalizerPreamp: Float = 0
    private(set) var equalizerGains = Array(
        repeating: Float(0),
        count: EqualizerConfiguration.frequencies.count
    )
    private(set) var equalizerFilters = EqualizerConfiguration.defaultFilters
    private(set) var equalizerBandwidths = EqualizerConfiguration.defaultBandwidths
    private(set) var equalizerPreset: EqualizerPreset = .original
    var errorMessage: String?
    var sleepTimerEnd: Date?

    private let player = AVPlayer()
    private let appleMusicPlayer = MPMusicPlayerController.applicationMusicPlayer
    private let pluginManager: PluginManager
    private let library: LibraryStore
    private let settings: AppSettings
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var sleepTimerTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var shuffleHistory: [Int] = []
    private var appleMusicProgressTimer: Timer?
    private var isUsingAppleMusicPlayer = false
    private var equalizerProcessor: AudioEqualizerProcessor?

    init(pluginManager: PluginManager, library: LibraryStore, settings: AppSettings) {
        self.pluginManager = pluginManager
        self.library = library
        self.settings = settings
        if let savedMode = UserDefaults.standard.string(forKey: "playbackMode").flatMap(PlaybackMode.init(rawValue:)) {
            playbackMode = savedMode
        }
        player.defaultRate = Float(settings.playbackRate)
        restoreEqualizerSettings()
        configureAudioSession()
        installObservers()
        configureRemoteCommands()
    }

    var hasPrevious: Bool { queue.count > 1 || progress > 3 }
    var hasNext: Bool { queue.count > 1 }
    var isEqualizerAvailable: Bool { !isUsingAppleMusicPlayer }

    var currentLyricIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        return lyrics.lastIndex { $0.time <= progress }
    }

    func play(_ track: MusicItem, in tracks: [MusicItem]? = nil) {
        if let tracks, !tracks.isEmpty {
            queue = tracks
            currentIndex = tracks.firstIndex { $0.stableID == track.stableID } ?? 0
            shuffleHistory = []
        } else if let existing = queue.firstIndex(where: { $0.stableID == track.stableID }) {
            currentIndex = existing
        } else {
            queue.append(track)
            currentIndex = queue.count - 1
            shuffleHistory = []
        }
        loadCurrent(autoplay: true)
    }

    func playAll(_ tracks: [MusicItem], startingAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = min(max(index, 0), tracks.count - 1)
        shuffleHistory = []
        loadCurrent(autoplay: true)
    }

    func playShuffled(_ tracks: [MusicItem]) {
        guard !tracks.isEmpty else { return }
        setPlaybackMode(.shuffle)
        playAll(tracks, startingAt: tracks.indices.randomElement() ?? 0)
    }

    func togglePlayback() {
        guard currentTrack != nil else {
            if !queue.isEmpty {
                currentIndex = currentIndex ?? 0
                loadCurrent(autoplay: true)
            }
            return
        }
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        if isUsingAppleMusicPlayer {
            appleMusicPlayer.play()
            appleMusicPlayer.currentPlaybackRate = Float(settings.playbackRate)
            isPlaying = true
            updateNowPlaying()
            return
        }
        guard player.currentItem != nil else {
            loadCurrent(autoplay: true)
            return
        }
        player.playImmediately(atRate: Float(settings.playbackRate))
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        if isUsingAppleMusicPlayer {
            appleMusicPlayer.pause()
        } else {
            player.pause()
        }
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        if isUsingAppleMusicPlayer {
            let target = min(max(time, 0), max(duration, 0))
            appleMusicPlayer.currentPlaybackTime = target
            progress = target
            updateNowPlaying()
            return
        }
        let target = CMTime(seconds: min(max(time, 0), max(duration, 0)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        progress = target.seconds
        updateNowPlaying()
    }

    func skipForward(_ seconds: TimeInterval = 15) { seek(to: progress + seconds) }
    func skipBackward(_ seconds: TimeInterval = 15) { seek(to: progress - seconds) }

    func next() {
        guard !queue.isEmpty else { return }
        if playbackMode == .shuffle {
            if queue.count == 1 {
                seek(to: 0)
                resume()
                return
            }
            if let currentIndex { shuffleHistory.append(currentIndex) }
            var candidate = Int.random(in: queue.indices)
            if candidate == currentIndex { candidate = (candidate + 1) % queue.count }
            currentIndex = candidate
        } else if let index = currentIndex, index + 1 < queue.count {
            currentIndex = index + 1
        } else if playbackMode == .repeatAll || playbackMode == .repeatOne {
            currentIndex = 0
        } else {
            pause()
            seek(to: 0)
            return
        }
        loadCurrent(autoplay: true)
    }

    func previous() {
        if progress > 4 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if playbackMode == .shuffle, let previousIndex = shuffleHistory.popLast(), queue.indices.contains(previousIndex) {
            currentIndex = previousIndex
        } else if let index = currentIndex, index > 0 {
            currentIndex = index - 1
        } else {
            currentIndex = playbackMode == .repeatAll || playbackMode == .repeatOne ? queue.count - 1 : 0
        }
        loadCurrent(autoplay: true)
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        shuffleHistory = []
        UserDefaults.standard.set(mode.rawValue, forKey: "playbackMode")
        updateNowPlaying()
    }

    func setPlaybackRate(_ rate: Double) {
        let validatedRate = min(max(rate.isFinite ? rate : 1, 0.5), 2.0)
        settings.playbackRate = validatedRate
        player.defaultRate = Float(validatedRate)

        if isUsingAppleMusicPlayer {
            if isPlaying {
                appleMusicPlayer.currentPlaybackRate = Float(validatedRate)
            }
        } else if isPlaying {
            player.playImmediately(atRate: Float(validatedRate))
        }
        updateNowPlaying()
    }

    func setEqualizerEnabled(_ enabled: Bool) {
        equalizerEnabled = enabled
        applyEqualizerConfiguration()
    }

    func selectEqualizerPreset(_ preset: EqualizerPreset) {
        guard preset != .custom else { return }
        let values = preset.configuration
        equalizerPreset = preset
        equalizerPreamp = values.preamp
        equalizerGains = values.gains
        equalizerFilters = values.filters
        equalizerBandwidths = values.bandwidths
        equalizerEnabled = true
        applyEqualizerConfiguration()
    }

    func setEqualizerGain(_ gain: Float, at index: Int) {
        guard equalizerGains.indices.contains(index) else { return }
        equalizerGains[index] = min(max(gain, -12), 12)
        equalizerPreset = .custom
        applyEqualizerConfiguration()
    }

    func setEqualizerPreamp(_ gain: Float) {
        equalizerPreamp = min(max(gain, -12), 6)
        equalizerPreset = .custom
        applyEqualizerConfiguration()
    }

    func cyclePlaybackMode() {
        switch playbackMode {
        case .sequential: setPlaybackMode(.repeatAll)
        case .repeatAll: setPlaybackMode(.repeatOne)
        case .repeatOne: setPlaybackMode(.shuffle)
        case .shuffle: setPlaybackMode(.sequential)
        }
    }

    func enqueueNext(_ track: MusicItem) {
        queue.removeAll { $0.stableID == track.stableID && $0.stableID != currentTrack?.stableID }
        let insertionIndex = min((currentIndex ?? -1) + 1, queue.count)
        queue.insert(track, at: insertionIndex)
        if let currentTrack { currentIndex = queue.firstIndex { $0.stableID == currentTrack.stableID } }
    }

    func moveQueueItems(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
        shuffleHistory = []
        if let track = currentTrack { currentIndex = queue.firstIndex { $0.stableID == track.stableID } }
    }

    func removeQueueItems(at offsets: IndexSet) {
        let currentID = currentTrack?.stableID
        queue.remove(atOffsets: offsets)
        shuffleHistory = []
        if let currentID, let index = queue.firstIndex(where: { $0.stableID == currentID }) {
            currentIndex = index
        } else if queue.isEmpty {
            stop()
        } else {
            currentIndex = min(currentIndex ?? 0, queue.count - 1)
        }
    }

    func stop() {
        loadTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        equalizerProcessor = nil
        appleMusicPlayer.stop()
        isUsingAppleMusicPlayer = false
        currentTrack = nil
        currentIndex = nil
        queue = []
        shuffleHistory = []
        progress = 0
        duration = 0
        lyrics = []
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        guard let minutes, minutes > 0 else {
            sleepTimerEnd = nil
            return
        }
        let end = Date.now.addingTimeInterval(Double(minutes) * 60)
        sleepTimerEnd = end
        sleepTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepTimerEnd = nil
        }
    }

    func refreshLyrics() async {
        guard let currentTrack else { return }
        do {
            let source = try await pluginManager.lyrics(for: currentTrack)
            guard self.currentTrack?.stableID == currentTrack.stableID else { return }
            lyricSource = source
            lyrics = LyricParser.parse(source)
        } catch {
            lyricSource = nil
            lyrics = []
        }
    }

    private func loadCurrent(autoplay: Bool) {
        loadTask?.cancel()
        guard let index = currentIndex, queue.indices.contains(index) else { return }
        let track = queue[index]
        currentTrack = track
        progress = 0
        duration = track.duration
        lyrics = []
        lyricSource = nil
        isLoading = true
        errorMessage = nil

        if track.raw.string("appleMusicPersistentID") != nil, library.localURL(for: track) == nil {
            loadAppleMusicTrack(track, autoplay: autoplay)
            return
        }
        isUsingAppleMusicPlayer = false
        appleMusicPlayer.stop()

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let playableTrack = await pluginManager.musicInfo(for: track)
                if let queueIndex = currentIndex, queue.indices.contains(queueIndex), queue[queueIndex].stableID == track.stableID {
                    queue[queueIndex] = playableTrack
                    currentTrack = playableTrack
                }
                let asset: AVURLAsset
                if let localURL = library.localURL(for: playableTrack) {
                    asset = AVURLAsset(url: localURL)
                } else {
                    let source = try await pluginManager.mediaSource(for: playableTrack, quality: settings.quality)
                    let options = source.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
                    asset = AVURLAsset(url: source.url, options: options)
                }
                guard !Task.isCancelled, currentTrack?.stableID == playableTrack.stableID else { return }
                let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
                let item = AVPlayerItem(asset: asset)
                item.audioTimePitchAlgorithm = .timeDomain
                installEqualizer(on: item, audioTrack: audioTrack)
                player.replaceCurrentItem(with: item)
                let loadedDuration = try? await asset.load(.duration).seconds
                if let loadedDuration, loadedDuration.isFinite, loadedDuration > 0 { duration = loadedDuration }
                isLoading = false
                library.recordPlayed(playableTrack)
                if autoplay { resume() }
                updateNowPlaying()
                Task { await self.refreshLyrics() }
                Task { await self.loadArtworkForNowPlaying(playableTrack) }
            } catch is CancellationError {
                return
            } catch {
                guard currentTrack?.stableID == track.stableID else { return }
                isLoading = false
                isPlaying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadAppleMusicTrack(_ track: MusicItem, autoplay: Bool) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        equalizerProcessor = nil
        isUsingAppleMusicPlayer = true

        if let storeID = track.raw.string("appleMusicStoreID"), !storeID.isEmpty {
            appleMusicPlayer.setQueue(with: [storeID])
        } else if let rawID = track.raw.string("appleMusicPersistentID"),
                  let persistentID = MPMediaEntityPersistentID(rawID),
                  let item = appleMusicItem(with: persistentID) {
            appleMusicPlayer.setQueue(with: MPMediaItemCollection(items: [item]))
        } else {
            isLoading = false
            isPlaying = false
            errorMessage = String(localized: "无法在 Apple Music 资料库中找到这首歌曲")
            return
        }

        appleMusicPlayer.prepareToPlay { [weak self] error in
            guard let service = self else { return }
            Task { @MainActor [service] in
                guard service.currentTrack?.stableID == track.stableID else { return }
                service.isLoading = false
                if let error {
                    service.isPlaying = false
                    service.errorMessage = error.localizedDescription
                    return
                }
                service.duration = service.appleMusicPlayer.nowPlayingItem?.playbackDuration ?? track.duration
                service.library.recordPlayed(track)
                if autoplay { service.resume() }
                service.updateNowPlaying()
                Task { await service.refreshLyrics() }
            }
        }
    }

    private func appleMusicItem(with persistentID: MPMediaEntityPersistentID) -> MPMediaItem? {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(
            MPMediaPropertyPredicate(
                value: NSNumber(value: persistentID),
                forProperty: MPMediaItemPropertyPersistentID,
                comparisonType: .equalTo
            )
        )
        return query.items?.first
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var equalizerConfiguration: EqualizerConfiguration {
        EqualizerConfiguration(
            isEnabled: equalizerEnabled,
            preamp: equalizerPreamp,
            gains: equalizerGains,
            filters: equalizerFilters,
            bandwidths: equalizerBandwidths
        )
    }

    private func installEqualizer(on item: AVPlayerItem, audioTrack: AVAssetTrack?) {
        guard let audioTrack else {
            equalizerProcessor = nil
            return
        }
        let processor = AudioEqualizerProcessor(configuration: equalizerConfiguration)
        guard let mix = processor.makeAudioMix(for: audioTrack) else {
            equalizerProcessor = nil
            return
        }
        item.audioMix = mix
        equalizerProcessor = processor
    }

    private func applyEqualizerConfiguration() {
        let configuration = equalizerConfiguration
        equalizerProcessor?.update(configuration: configuration)
        let defaults = UserDefaults.standard
        defaults.set(equalizerEnabled, forKey: "equalizerEnabled")
        defaults.set(Double(equalizerPreamp), forKey: "equalizerPreamp")
        defaults.set(equalizerGains.map(Double.init), forKey: "equalizerGains")
        defaults.set(equalizerFilters.map(\.rawValue), forKey: "equalizerFilters")
        defaults.set(equalizerBandwidths.map(Double.init), forKey: "equalizerBandwidths")
        defaults.set(equalizerPreset.rawValue, forKey: "equalizerPreset")
    }

    private func restoreEqualizerSettings() {
        let defaults = UserDefaults.standard
        equalizerEnabled = defaults.bool(forKey: "equalizerEnabled")
        equalizerPreamp = min(
            max(Float(defaults.object(forKey: "equalizerPreamp") as? Double ?? 0), -12),
            6
        )
        if let savedGains = defaults.array(forKey: "equalizerGains") as? [NSNumber],
           savedGains.count == EqualizerConfiguration.frequencies.count {
            equalizerGains = savedGains.map { min(max($0.floatValue, -12), 12) }
        }
        if let savedFilters = defaults.stringArray(forKey: "equalizerFilters"),
           savedFilters.count == EqualizerConfiguration.frequencies.count {
            equalizerFilters = savedFilters.map { EqualizerFilter(rawValue: $0) ?? .peak }
        }
        if let savedBandwidths = defaults.array(forKey: "equalizerBandwidths") as? [NSNumber],
           savedBandwidths.count == EqualizerConfiguration.frequencies.count {
            equalizerBandwidths = savedBandwidths.map { min(max($0.floatValue, 0.1), 5) }
        }
        equalizerPreset = defaults.string(forKey: "equalizerPreset")
            .flatMap(EqualizerPreset.init(rawValue:)) ?? .original
    }

    private func installObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.4, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.progress = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.isPlaying = self.player.rate > 0
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }
                if self.playbackMode == .repeatOne {
                    self.seek(to: 0)
                    self.resume()
                } else {
                    self.next()
                }
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }
        appleMusicProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isUsingAppleMusicPlayer else { return }
                let wasPlaying = self.isPlaying
                self.progress = max(self.appleMusicPlayer.currentPlaybackTime, 0)
                self.duration = self.appleMusicPlayer.nowPlayingItem?.playbackDuration ?? self.duration
                self.isPlaying = self.appleMusicPlayer.playbackState == .playing
                if self.isPlaying,
                   abs(self.appleMusicPlayer.currentPlaybackRate - Float(self.settings.playbackRate)) > 0.001 {
                    self.appleMusicPlayer.currentPlaybackRate = Float(self.settings.playbackRate)
                }
                if wasPlaying, self.appleMusicPlayer.playbackState == .stopped {
                    self.next()
                    return
                }
                self.updateNowPlaying()
            }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if settings.continueAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                resume()
            }
        @unknown default: break
        }
    }

    private func updateNowPlaying(artwork: MPMediaItemArtwork? = nil) {
        guard let track = currentTrack else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? settings.playbackRate : 0
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtworkForNowPlaying(_ track: MusicItem) async {
        guard let url = ArtworkURL.resolve(track.artwork), url.scheme?.hasPrefix("http") == true else { return }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Sonnets/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let scheme = url.scheme, let host = url.host {
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request), let image = UIImage(data: data) else { return }
        guard currentTrack?.stableID == track.stableID else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        updateNowPlaying(artwork: artwork)
    }
}
