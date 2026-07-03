import AppKit
import SwiftUI

/// Top-level settings window router that loads the appropriate interface based on the active theme.
struct SettingsView: View {
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    
    private var currentTheme: AppTheme {
        AppTheme(rawValue: currentThemeRaw) ?? .classic
    }

    var body: some View {
        Group {
            if currentTheme == .classic {
                ClassicSettingsView()
            } else {
                ModernSettingsView()
            }
        }
        .id(currentTheme)
        .onAppear { forceWindowAppearance() }
        .onChangeCompat(of: currentTheme) { _ in forceWindowAppearance() }
    }
    
    private func forceWindowAppearance() {
        DispatchQueue.main.async {
            NSApp.appearance = currentTheme == .classic ? NSAppearance(named: .darkAqua) : nil
            for window in NSApp.windows where window.title == "Settings" || String(describing: type(of: window)) == "SettingsWindow" {
                window.appearance = currentTheme == .classic ? NSAppearance(named: .darkAqua) : nil
                window.contentView?.needsDisplay = true
                window.displayIfNeeded()
            }
        }
    }
}
