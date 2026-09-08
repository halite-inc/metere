//
//  metereApp.swift
//  metere
//
//  Created by Vijay on 07/09/26.
//

import SwiftUI

@main
struct metereApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView(appState: appState)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Metere Statistics", id: "statistics") {
            StatisticsWindowView(appState: appState)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
