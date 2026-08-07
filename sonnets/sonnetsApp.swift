//
//  sonnetsApp.swift
//  sonnets
//
//  Created by Zhuanz密码0000 on 7/30/26.
//

import SwiftUI

@main
struct sonnetsApp: App {
    @State private var plugins: PluginManager
    @State private var library: LibraryStore
    @State private var settings: AppSettings
    @State private var player: PlayerService

    init() {
        let plugins = PluginManager()
        let library = LibraryStore()
        let settings = AppSettings()
        let player = PlayerService(pluginManager: plugins, library: library, settings: settings)
        _plugins = State(initialValue: plugins)
        _library = State(initialValue: library)
        _settings = State(initialValue: settings)
        _player = State(initialValue: player)
    }

    var body: some Scene {
        WindowGroup {
            PlayerContainerView()
                .environment(plugins)
                .environment(library)
                .environment(settings)
                .environment(player)
        }
    }
}
