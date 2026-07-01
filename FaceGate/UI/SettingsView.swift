import AppKit
import SwiftUI

/// Top-level settings window router that loads the appropriate interface based on the active theme.
struct SettingsView: View {
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    
    private var currentTheme: AppTheme {
        AppTheme(rawValue: currentThemeRaw) ?? .classic
    }

    var body: some View {
        if currentTheme == .classic {
            ClassicSettingsView()
        } else {
            ModernSettingsView()
        }
    }
}
