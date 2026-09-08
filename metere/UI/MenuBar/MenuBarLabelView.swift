//
//  MenuBarLabelView.swift
//  metere
//

import SwiftUI

public struct MenuBarLabelView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState = .shared) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.isHeadphoneConnected ? .primary : .secondary)

            if appState.settings.showDecibelsInMenuBar {
                Text(appState.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
