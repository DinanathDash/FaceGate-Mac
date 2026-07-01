import Foundation

/// Represents the UI theme for FaceGate.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case modern = "Modern"
    
    var id: String { rawValue }
    
    /// The currently selected theme.
    static var current: AppTheme {
        get {
            let value = UserDefaults.standard.string(forKey: FGConstants.appThemeKey) ?? AppTheme.classic.rawValue
            return AppTheme(rawValue: value) ?? .classic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: FGConstants.appThemeKey)
        }
    }
}
