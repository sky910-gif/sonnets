import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @State private var exportDocument: LibraryBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false

    var body: some View {
        @Bindable var settings = settings
        let playbackRateBinding = Binding<Double>(
            get: { settings.playbackRate },
            set: { player.setPlaybackRate($0) }
        )
        ZStack {
            AppBackground()
            Form {
                Section("音乐来源") {
                    NavigationLink { PluginSettingsView() } label: {
                        Label("插件设置", systemImage: "puzzlepiece.extension.fill")
                    }
                }
                Section("播放") {
                    Picker("默认音质", selection: $settings.quality) {
                        ForEach(AudioQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("播放速度", selection: playbackRateBinding) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { Text("\($0, specifier: "%.2g")×").tag($0) }
                    }
                    Toggle("中断后自动继续", isOn: $settings.continueAfterInterruption)
                }
                Section("外观") {
                    Picker("显示模式", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("播放界面", selection: $settings.nowPlayingStyle) {
                        ForEach(NowPlayingStyle.allCases) { style in
                            Label(style.title, systemImage: style.symbol).tag(style)
                        }
                    }
                    LabeledContent("界面材质", value: "Liquid Glass")
                }
                Section("数据") {
                    Button("导出资料库", systemImage: "square.and.arrow.up") {
                        if let data = try? library.exportData() {
                            exportDocument = LibraryBackupDocument(data: data)
                            showExporter = true
                        }
                    }
                    Button("导入备份", systemImage: "square.and.arrow.down") { showImporter = true }
                }
                Section("关于") {
                    LabeledContent("应用", value: "Sonnets")
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("播放器遵循本地优先原则，不内置任何音乐平台或音源。网络插件及其内容由用户自行选择，请在合法授权范围内使用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .sonnetsBackup,
            defaultFilename: String(localized: "Sonnets-资料库")
        ) { _ in }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.sonnetsBackup, .json]) { result in
            guard case .success(let url) = result else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { try? library.restore(from: data) }
        }
    }
}

struct PluginSettingsView: View {
    @Environment(PluginManager.self) private var plugins
    @State private var sourceURL = PluginManager.defaultSourceURL
    @State private var editingVariablesPlugin: InstalledPlugin?
    @State private var pluginToDelete: InstalledPlugin?
    @State private var pluginToRename: InstalledPlugin?
    @State private var renamedPlatform = ""
    @State private var showError = false

    var body: some View {
        @Bindable var plugins = plugins
        ZStack {
            AppBackground()
            List {
                Section("网络插件源") {
                    TextField("插件源 JSON 或插件 JS 地址", text: $sourceURL, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            do { try await plugins.importSource(sourceURL) }
                            catch { plugins.lastError = error.localizedDescription; showError = true }
                        }
                    } label: {
                        HStack {
                            if plugins.isWorking { ProgressView().controlSize(.small) }
                            Label(
                                plugins.isWorking ? plugins.statusMessage : String(localized: "导入或更新插件源"),
                                systemImage: "square.and.arrow.down"
                            )
                        }
                    }
                    .disabled(plugins.isWorking || sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    ForEach(plugins.subscriptions) { subscription in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subscription.title)
                            Text(subscription.url).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }

                Section("已安装插件 · 可编辑排序") {
                    if plugins.plugins.isEmpty {
                        Text("尚未安装插件").foregroundStyle(.secondary)
                    }
                    ForEach(plugins.plugins) { plugin in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(plugin.name).font(.headline)
                                    if plugin.name != plugin.platformIdentifier {
                                        Text("原名称：\(plugin.platformIdentifier)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text([plugin.manifest.author, plugin.manifest.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("启用", isOn: Binding(
                                    get: { plugin.enabled },
                                    set: { plugins.setEnabled(plugin, enabled: $0) }
                                ))
                                .labelsHidden()
                            }
                            HStack(spacing: 7) {
                                ForEach(plugin.manifest.supportedSearchTypes.prefix(5)) { type in
                                    Text(type.title).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
                                }
                            }
                            HStack {
                                if !plugin.manifest.userVariables.isEmpty {
                                    Button("变量") { editingVariablesPlugin = plugin }.buttonStyle(.bordered)
                                }
                                Button("重命名") {
                                    renamedPlatform = plugin.name
                                    pluginToRename = plugin
                                }
                                .buttonStyle(.bordered)
                                Button("更新") {
                                    Task {
                                        do { try await plugins.update(plugin) }
                                        catch { plugins.lastError = error.localizedDescription; showError = true }
                                    }
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button("删除", role: .destructive) { pluginToDelete = plugin }.buttonStyle(.bordered)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: plugins.movePlugins)
                }

                Section("安全说明") {
                    Text("插件在独立 JavaScriptCore 环境中运行，只获得 HTTP/HTTPS 网络访问能力，不会获得相册、通讯录或任意文件访问权限。请仍然只安装可信来源。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("插件设置")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("默认插件", selection: $plugins.selectedPluginID) {
                        Text("自动").tag(UUID?.none)
                        ForEach(plugins.enabledPlugins) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("刷新全部", systemImage: "arrow.clockwise") { Task { await plugins.refreshSubscriptions() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editingVariablesPlugin) { plugin in PluginVariablesView(plugin: plugin) }
        .alert(
            "重命名平台",
            isPresented: Binding(
                get: { pluginToRename != nil },
                set: { if !$0 { pluginToRename = nil } }
            )
        ) {
            TextField("平台显示名称", text: $renamedPlatform)
            Button("取消", role: .cancel) { pluginToRename = nil }
            Button("保存") {
                if let pluginToRename { plugins.rename(pluginToRename, to: renamedPlatform) }
                pluginToRename = nil
            }
        } message: {
            Text("只更改 Sonnets 中的显示名称，不会修改插件本身。清空可恢复原名称。")
        }
        .confirmationDialog("删除插件？", isPresented: Binding(get: { pluginToDelete != nil }, set: { if !$0 { pluginToDelete = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let pluginToDelete { plugins.remove(pluginToDelete) }
                pluginToDelete = nil
            }
        } message: {
            Text("删除后需要从插件源重新安装。收藏和歌单数据会保留。")
        }
        .alert("操作失败", isPresented: $showError) {
            Button("好") {}
        } message: { Text(plugins.lastError ?? String(localized: "未知错误")) }
    }
}

struct PluginVariablesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluginManager.self) private var plugins
    let plugin: InstalledPlugin
    @State private var values: [String: String]
    @State private var isSaving = false

    init(plugin: InstalledPlugin) {
        self.plugin = plugin
        _values = State(initialValue: plugin.userVariables)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(plugin.manifest.userVariables) { variable in
                    Section(variable.name ?? variable.key) {
                        TextField(variable.hint ?? "请输入", text: Binding(
                            get: { values[variable.key] ?? "" },
                            set: { values[variable.key] = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle(plugin.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        isSaving = true
                        Task {
                            try? await plugins.setUserVariables(values, for: plugin)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}

struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sonnetsBackup, .json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension UTType {
    static let sonnetsBackup = UTType(exportedAs: "app.sonnets.backup", conformingTo: .json)
}
