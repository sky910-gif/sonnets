import SwiftUI

struct EqualizerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerService.self) private var player

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    curveCard
                    presetPicker
                    bandControls
                    preampControl
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .background(equalizerBackground)
            .navigationTitle("AUTOEQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black.opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                AmbientRecordArtwork(artwork: player.currentTrack?.artwork)
                    .frame(width: 72, height: 72)
                    .overlay {
                        Circle()
                            .stroke(accent.opacity(0.48), lineWidth: 1)
                            .padding(2)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTOEQ // SIGNAL LAB")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(accent)
                    Text(player.currentTrack?.title ?? String(localized: "未在播放"))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(player.currentTrack?.artist ?? String(localized: "选择歌曲后生成专属响应"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(player.equalizerEnabled ? "DSP LINKED · \(player.equalizerPreset.title)" : "BYPASS · ORIGINAL SIGNAL")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(player.equalizerEnabled ? .green : .white.opacity(0.46))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Label(player.equalizerEnabled ? "ENGINE ACTIVE" : "ENGINE STANDBY", systemImage: "waveform.path.ecg")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(player.equalizerEnabled ? accent : .white.opacity(0.48))
                Spacer()
                Toggle(
                    "均衡器",
                    isOn: Binding(
                        get: { player.equalizerEnabled },
                        set: player.setEqualizerEnabled
                    )
                )
                .font(.caption.weight(.semibold))
                .tint(accent)
                .disabled(!player.isEqualizerAvailable)
            }

            if !player.isEqualizerAvailable {
                Label(
                    "系统 Apple Music 播放不支持应用内音效；切换到在线歌曲或本地文件后即可使用。",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(17)
        .background {
            ZStack {
                panelFill
                LinearGradient(colors: [accent.opacity(0.14), .clear, .indigo.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.38), lineWidth: 1)
        }
        .padding(.top, 8)
    }

    private var curveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET RESPONSE")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(accent)
                    Text("实时频响预览")
                        .font(.headline)
                    Text("AutoEq 风格的参数响应")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("前级 \(signedDecibels(player.equalizerPreamp))")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            }

            EqualizerCurveGraph(
                gains: player.equalizerGains,
                isEnabled: player.equalizerEnabled
            )
            .frame(height: 176)
        }
        .padding(16)
        .background(.black.opacity(0.62), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("REFERENCE TARGET")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(accent)
            Text("选择听感目标")
                .font(.headline)
            Text("采用 AutoEq 的 PEQ 表达方式；耳机实测校准需另行匹配型号。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(EqualizerPreset.selectablePresets) { preset in
                        let isSelected = player.equalizerPreset == preset
                        Button {
                            player.selectEqualizerPreset(preset)
                        } label: {
                            Label(preset.title, systemImage: preset.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.84))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(
                                    isSelected ? accent : Color.white.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? accent.opacity(0.8) : .white.opacity(0.10), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .disabled(!player.isEqualizerAvailable)
        .opacity(player.isEqualizerAvailable ? 1 : 0.45)
    }

    private var bandControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PARAMETRIC BANDS")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(accent)
                    Text("频段")
                        .font(.headline)
                }
                Spacer()
                Text("-12 至 +12 dB")
                    .font(.caption)
                    .foregroundStyle(accent)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EqualizerConfiguration.frequencies.indices, id: \.self) { index in
                        EqualizerBandControl(
                            frequency: EqualizerConfiguration.frequencies[index],
                            gain: player.equalizerGains[index],
                            filter: player.equalizerFilters[index],
                            isEnabled: player.equalizerEnabled && player.isEqualizerAvailable
                        ) { gain in
                            player.setEqualizerGain(gain, at: index)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .background(panelFill, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var preampControl: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEADROOM")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(accent)
                    Text("前级增益")
                        .font(.headline)
                    Text("自动留出余量以减少削波与失真")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(signedDecibels(player.equalizerPreamp))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent)
            }

            Slider(
                value: Binding(
                    get: { Double(player.equalizerPreamp) },
                    set: { player.setEqualizerPreamp(Float($0)) }
                ),
                in: -12...6,
                step: 0.5
            )
            .tint(accent)

            Button {
                player.selectEqualizerPreset(.original)
            } label: {
                Label("恢复原声", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(panelFill, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .disabled(!player.isEqualizerAvailable)
        .opacity(player.isEqualizerAvailable ? 1 : 0.45)
    }

    private var equalizerBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [.black, Color(red: 0.015, green: 0.03, blue: 0.055)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [.indigo.opacity(0.11), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private func signedDecibels(_ gain: Float) -> String {
        let prefix = gain > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", Double(gain))) dB"
    }

    private var accent: Color { Color(red: 0.24, green: 0.95, blue: 0.46) }
    private var panelFill: Color { Color.white.opacity(0.055) }
}

private struct EqualizerCurveGraph: View {
    let gains: [Float]
    let isEnabled: Bool

    var body: some View {
        Canvas { context, size in
            let chart = CGRect(x: 0, y: 10, width: size.width, height: size.height - 30)
            drawGrid(in: chart, context: &context)
            drawCurve(in: chart, context: &context)
        }
        .overlay(alignment: .bottom) {
            HStack {
                Text("31")
                Spacer()
                Text("250")
                Spacer()
                Text("1k")
                Spacer()
                Text("4k")
                Spacer()
                Text("16k Hz")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.green.opacity(0.74))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("均衡器频响曲线")
        .accessibilityValue(isEnabled ? String(localized: "已启用") : String(localized: "已关闭"))
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext) {
        for row in 0...4 {
            let y = rect.minY + rect.height * CGFloat(row) / 4
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(
                path,
                with: .color(row == 2 ? .green.opacity(0.44) : .green.opacity(0.16)),
                lineWidth: row == 2 ? 1.2 : 0.7
            )
        }
        for column in 0..<gains.count {
            let x = xPosition(for: column, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(.green.opacity(0.12)), lineWidth: 0.7)
        }
    }

    private func drawCurve(in rect: CGRect, context: inout GraphicsContext) {
        guard !gains.isEmpty else { return }
        let points = gains.indices.map { index in
            CGPoint(
                x: xPosition(for: index, in: rect),
                y: rect.midY - CGFloat(min(max(gains[index], -12), 12)) / 24 * rect.height
            )
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midpoint, y: previous.y),
                control2: CGPoint(x: midpoint, y: current.y)
            )
        }
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [.green, Color(red: 0.12, green: 0.80, blue: 0.34)]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
        for point in points {
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)),
                with: .color(isEnabled ? .green : .gray)
            )
        }
    }

    private func xPosition(for index: Int, in rect: CGRect) -> CGFloat {
        guard gains.count > 1 else { return rect.midX }
        return rect.minX + rect.width * CGFloat(index) / CGFloat(gains.count - 1)
    }
}

private struct EqualizerBandControl: View {
    let frequency: Float
    let gain: Float
    let filter: EqualizerFilter
    let isEnabled: Bool
    let onChange: (Float) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(signedGain)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(isEnabled ? Color.green : Color.secondary)

            Text(filter == .peak ? "PEQ" : filter.label == "LOW SHELF" ? "LS" : "HS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))

            GeometryReader { proxy in
                let thumbY = yPosition(in: proxy.size.height)
                ZStack {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(width: 4)
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 14, height: 1)
                    Circle()
                        .fill(isEnabled ? Color.green : Color.gray)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .position(x: proxy.size.width / 2, y: thumbY)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard isEnabled else { return }
                            let normalized = 1 - min(max(value.location.y / proxy.size.height, 0), 1)
                            let stepped = ((normalized * 24 - 12) * 2).rounded() / 2
                            onChange(Float(stepped))
                        }
                )
            }
            .frame(width: 38, height: 154)

            Text(frequencyLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.green.opacity(0.74))
                .frame(width: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(frequencyLabel) 赫兹")
        .accessibilityValue(signedGain)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onChange(min(gain + 0.5, 12))
            case .decrement: onChange(max(gain - 0.5, -12))
            @unknown default: break
            }
        }
    }

    private func yPosition(in height: CGFloat) -> CGFloat {
        let normalized = CGFloat((min(max(gain, -12), 12) + 12) / 24)
        return max(11, min(height - 11, height * (1 - normalized)))
    }

    private var signedGain: String {
        let prefix = gain > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", Double(gain)))"
    }

    private var frequencyLabel: String {
        switch frequency {
        case 1_000: "1k"
        case 2_000: "2k"
        case 4_000: "4k"
        case 8_000: "8k"
        case 16_000: "16k"
        default: "\(Int(frequency))"
        }
    }
}

#Preview {
    let plugins = PluginManager()
    let library = LibraryStore()
    let settings = AppSettings()
    let player = PlayerService(pluginManager: plugins, library: library, settings: settings)
    EqualizerView()
        .environment(player)
}
