import AudioToolbox
import AVFoundation
import MediaToolbox

enum EqualizerFilter: String, Sendable {
    case peak
    case lowShelf
    case highShelf

    var audioUnitValue: AudioUnitParameterValue {
        switch self {
        case .peak: AudioUnitParameterValue(kAUNBandEQFilterType_Parametric)
        case .lowShelf: AudioUnitParameterValue(kAUNBandEQFilterType_LowShelf)
        case .highShelf: AudioUnitParameterValue(kAUNBandEQFilterType_HighShelf)
        }
    }

    var label: String {
        switch self {
        case .peak: "PEAK"
        case .lowShelf: "LOW SHELF"
        case .highShelf: "HIGH SHELF"
        }
    }
}

struct EqualizerConfiguration: Sendable {
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    var isEnabled: Bool
    var preamp: Float
    var gains: [Float]
    var filters: [EqualizerFilter]
    var bandwidths: [Float]

    static let flat = EqualizerConfiguration(
        isEnabled: false,
        preamp: 0,
        gains: Array(repeating: 0, count: frequencies.count),
        filters: Self.defaultFilters,
        bandwidths: Self.defaultBandwidths
    )

    static let defaultFilters: [EqualizerFilter] = [
        .lowShelf, .peak, .peak, .peak, .peak,
        .peak, .peak, .peak, .peak, .highShelf
    ]
    static let defaultBandwidths: [Float] = [1.0, 1.25, 1.35, 1.45, 1.5, 1.5, 1.35, 1.2, 1.1, 0.9]
}

enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case reference
    case immersive
    case bass
    case vocal
    case clarity
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: String(localized: "原声")
        case .reference: String(localized: "参考中性")
        case .immersive: String(localized: "沉浸低频")
        case .bass: String(localized: "低音增强")
        case .vocal: String(localized: "人声")
        case .clarity: String(localized: "空气感")
        case .custom: String(localized: "自定义")
        }
    }

    var symbol: String {
        switch self {
        case .original: "waveform"
        case .reference: "scope"
        case .immersive: "waveform.path.ecg"
        case .bass: "speaker.wave.3.fill"
        case .vocal: "person.wave.2.fill"
        case .clarity: "sparkles"
        case .custom: "slider.vertical.3"
        }
    }

    /// Curves are authored in the same PEQ vocabulary as AutoEq exports: a
    /// protective preamp, shelf filters at the extremes and peaking filters
    /// through the mids. Actual headphone correction still requires a chosen
    /// headphone measurement, so these remain target-style listening curves.
    var configuration: (preamp: Float, gains: [Float], filters: [EqualizerFilter], bandwidths: [Float]) {
        switch self {
        case .original:
            (0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .reference:
            (-5.5, [3.5, 1.5, -1, -1.5, 0.5, 2, 2.5, 1.5, -1, 1], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .immersive:
            (-6, [6, 4, 1, -1, -1, 0, 1.5, 3, 2.5, 2], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .bass:
            (-5, [6, 5, 3.5, 1, -1, -1, 0, 1, 1, 0], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .vocal:
            (-4, [-2, -1, 0, 1, 2.5, 4, 3, 1, -1, -2], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .clarity:
            (-4.5, [-2, -1, 0, 0.5, 1, 2, 3.5, 4, 3, 2], EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        case .custom:
            (0, Array(repeating: 0, count: EqualizerConfiguration.frequencies.count), EqualizerConfiguration.defaultFilters, EqualizerConfiguration.defaultBandwidths)
        }
    }

    static var selectablePresets: [EqualizerPreset] {
        allCases.filter { $0 != .custom }
    }
}

final class AudioEqualizerProcessor: @unchecked Sendable {
    private let context: AudioEqualizerTapContext
    private(set) var tap: MTAudioProcessingTap?

    init(configuration: EqualizerConfiguration) {
        context = AudioEqualizerTapContext(configuration: configuration)
    }

    func makeAudioMix(for track: AVAssetTrack) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(context).toOpaque(),
            init: equalizerTapInit,
            finalize: equalizerTapFinalize,
            prepare: equalizerTapPrepare,
            unprepare: equalizerTapUnprepare,
            process: equalizerTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr, let tap else { return nil }

        self.tap = tap
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    func update(configuration: EqualizerConfiguration) {
        context.update(configuration: configuration)
    }
}

private final class AudioEqualizerTapContext: @unchecked Sendable {
    private var configuration: EqualizerConfiguration
    private var audioUnit: AudioUnit?
    private var sampleTime: Float64 = 0
    private let lock = NSLock()

    init(configuration: EqualizerConfiguration) {
        self.configuration = configuration
    }

    func update(configuration: EqualizerConfiguration) {
        lock.lock()
        self.configuration = configuration
        if let audioUnit {
            apply(configuration, to: audioUnit)
        }
        lock.unlock()
    }

    func prepare(maxFrames: CMItemCount, format: AudioStreamBasicDescription) {
        lock.lock()
        defer { lock.unlock() }
        disposeAudioUnit()

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_NBandEQ,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { return }

        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else { return }

        var bandCount = UInt32(EqualizerConfiguration.frequencies.count)
        var mutableFormat = format
        var maximumFrames = UInt32(clamping: maxFrames)
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        guard AudioUnitSetProperty(
            unit,
            kAUNBandEQProperty_NumberOfBands,
            kAudioUnitScope_Global,
            0,
            &bandCount,
            propertySize
        ) == noErr,
        AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &mutableFormat,
            formatSize
        ) == noErr,
        AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            0,
            &mutableFormat,
            formatSize
        ) == noErr,
        AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            propertySize
        ) == noErr else {
            AudioComponentInstanceDispose(unit)
            return
        }

        for index in EqualizerConfiguration.frequencies.indices {
            AudioUnitSetParameter(
                unit,
                kAUNBandEQParam_BypassBand + AudioUnitParameterID(index),
                kAudioUnitScope_Global,
                0,
                0,
                0
            )
            let filter = configuration.filters.indices.contains(index)
                ? configuration.filters[index]
                : .peak
            let bandwidth = configuration.bandwidths.indices.contains(index)
                ? min(max(configuration.bandwidths[index], 0.1), 5)
                : 1
            AudioUnitSetParameter(
                unit,
                kAUNBandEQParam_FilterType + AudioUnitParameterID(index),
                kAudioUnitScope_Global,
                0,
                filter.audioUnitValue,
                0
            )
            AudioUnitSetParameter(
                unit,
                kAUNBandEQParam_Frequency + AudioUnitParameterID(index),
                kAudioUnitScope_Global,
                0,
                EqualizerConfiguration.frequencies[index],
                0
            )
            AudioUnitSetParameter(
                unit,
                kAUNBandEQParam_Bandwidth + AudioUnitParameterID(index),
                kAudioUnitScope_Global,
                0,
                bandwidth,
                0
            )
        }
        apply(configuration, to: unit)

        guard AudioUnitInitialize(unit) == noErr else {
            AudioComponentInstanceDispose(unit)
            return
        }
        sampleTime = 0
        audioUnit = unit
    }

    func unprepare() {
        lock.lock()
        disposeAudioUnit()
        lock.unlock()
    }

    func process(
        tap: MTAudioProcessingTap,
        requestedFrames: CMItemCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        var sourceFlags = MTAudioProcessingTapFlags()
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            requestedFrames,
            bufferList,
            &sourceFlags,
            nil,
            framesOut
        )
        flagsOut.pointee = sourceFlags
        guard status == noErr, framesOut.pointee > 0, let audioUnit else {
            if status != noErr { framesOut.pointee = 0 }
            return
        }

        if sourceFlags & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream) != 0 {
            AudioUnitReset(audioUnit, kAudioUnitScope_Global, 0)
            sampleTime = 0
        }
        var actionFlags = AudioUnitRenderActionFlags()
        var timeStamp = AudioTimeStamp(
            mSampleTime: sampleTime,
            mHostTime: 0,
            mRateScalar: 0,
            mWordClockTime: 0,
            mSMPTETime: SMPTETime(),
            mFlags: .sampleTimeValid,
            mReserved: 0
        )
        AudioUnitProcess(
            audioUnit,
            &actionFlags,
            &timeStamp,
            UInt32(clamping: framesOut.pointee),
            bufferList
        )
        sampleTime += Float64(framesOut.pointee)
    }

    private func apply(_ configuration: EqualizerConfiguration, to unit: AudioUnit) {
        let gains = normalizedGains(configuration.gains)
        let activePreamp = configuration.isEnabled ? configuration.preamp : 0
        AudioUnitSetParameter(
            unit,
            kAUNBandEQParam_GlobalGain,
            kAudioUnitScope_Global,
            0,
            activePreamp,
            0
        )
        for index in gains.indices {
            AudioUnitSetParameter(
                unit,
                kAUNBandEQParam_Gain + AudioUnitParameterID(index),
                kAudioUnitScope_Global,
                0,
                configuration.isEnabled ? gains[index] : 0,
                0
            )
        }
    }

    private func normalizedGains(_ gains: [Float]) -> [Float] {
        EqualizerConfiguration.frequencies.indices.map { index in
            gains.indices.contains(index) ? min(max(gains[index], -12), 12) : 0
        }
    }

    private func disposeAudioUnit() {
        guard let audioUnit else { return }
        AudioUnitUninitialize(audioUnit)
        AudioComponentInstanceDispose(audioUnit)
        self.audioUnit = nil
    }
}

private let equalizerTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    guard let clientInfo else { return }
    tapStorageOut.pointee = Unmanaged<AudioEqualizerTapContext>
        .fromOpaque(clientInfo)
        .retain()
        .toOpaque()
}

private let equalizerTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<AudioEqualizerTapContext>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .release()
}

private let equalizerTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, format in
    let context = Unmanaged<AudioEqualizerTapContext>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()
    context.prepare(maxFrames: maxFrames, format: format.pointee)
}

private let equalizerTapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    let context = Unmanaged<AudioEqualizerTapContext>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()
    context.unprepare()
}

private let equalizerTapProcess: MTAudioProcessingTapProcessCallback = {
    tap,
    requestedFrames,
    _,
    bufferList,
    framesOut,
    flagsOut in
    let context = Unmanaged<AudioEqualizerTapContext>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()
    context.process(
        tap: tap,
        requestedFrames: requestedFrames,
        bufferList: bufferList,
        framesOut: framesOut,
        flagsOut: flagsOut
    )
}
