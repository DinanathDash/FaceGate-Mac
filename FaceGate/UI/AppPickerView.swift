import SwiftUI

/// A router component that renders the classic or modern app picker based on theme.
struct AppPickerView: View {
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    
    /// Called when the user wants to configure the app (e.g., set timer)
    var onClickApp: ((LockedApp) -> Void)?
    
    private var currentTheme: AppTheme {
        AppTheme(rawValue: currentThemeRaw) ?? .classic
    }

    var body: some View {
        if currentTheme == .classic {
            ClassicAppPicker()
        } else {
            ModernAppPicker(onClickApp: onClickApp)
        }
    }
}
