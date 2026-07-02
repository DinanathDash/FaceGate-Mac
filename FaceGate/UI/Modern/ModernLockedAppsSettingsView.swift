import SwiftUI
import AppKit

struct ModernLockedAppsSettingsView: View {
    @ObservedObject var lockedAppsManager = LockedAppsManager.shared
    @State private var editingApp: LockedApp?

    var body: some View {
        VStack(spacing: 0) {
            AppPickerView { app in
                editingApp = app
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .sheet(item: $editingApp) { app in
            LockedAppSheetView(app: app, isPresented: Binding(
                get: { editingApp != nil },
                set: { if !$0 { editingApp = nil } }
            ))
        }
    }
}

private struct LockedAppSheetView: View {
    let app: LockedApp
    @Binding var isPresented: Bool
    
    @ObservedObject var lockedAppsManager = LockedAppsManager.shared
    
    @State private var hasCustomTimer = false
    @State private var customTimeoutMinutes: Double = 5
    @State private var appTimerMode: Int = 0 // 0=global, 1=fromUnlock, 2=fromFocus
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                Text("Configure Timer: \(app.displayName)")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Custom Session Timer")
                            .font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $hasCustomTimer)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    
                    Text("Override the global timer for this specific app.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if hasCustomTimer {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Timer Duration")
                                .font(.system(size: 13))
                            Spacer(minLength: 16)
                            Picker("", selection: $customTimeoutMinutes) {
                                Text("Immediately").tag(0.0)
                                Text("For 1 minute").tag(1.0)
                                Text("For 2 minutes").tag(2.0)
                                Text("For 3 minutes").tag(3.0)
                                Text("For 5 minutes").tag(5.0)
                                Text("For 10 minutes").tag(10.0)
                                Text("For 20 minutes").tag(20.0)
                                Text("For 30 minutes").tag(30.0)
                                Text("For 1 hour").tag(60.0)
                                Text("For 1 hour, 30 minutes").tag(90.0)
                                Text("For 2 hours").tag(120.0)
                                Text("For 2 hours, 30 minutes").tag(150.0)
                                Text("For 3 hours").tag(180.0)
                                Divider()
                                Text("Never").tag(FGConstants.indefiniteSliderValue)
                            }
                            .frame(width: 200)
                        }
                        
                        if customTimeoutMinutes > 0 && customTimeoutMinutes < FGConstants.indefiniteSliderValue {
                            HStack {
                                Text("Timer Mode")
                                    .font(.system(size: 13))
                                Spacer(minLength: 16)
                                Picker("", selection: $appTimerMode) {
                                    Text("Use Global Setting").tag(0)
                                    Text("From last unlock").tag(1)
                                    Text("From when app loses focus").tag(2)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                            }
                            
                            switch appTimerMode {
                            case 1:
                                Text("The timer counts total elapsed time since unlock, regardless of whether you're actively using the app.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            case 2:
                                Text("The timer only counts down while the app is not in focus. Switch away for the full duration to trigger a lock.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            default:
                                let globalMode = UserDefaults.standard.bool(forKey: FGConstants.sessionTimerFromFocusKey)
                                if globalMode {
                                    Text("Global setting: The timer only counts down while the app is not in focus. Switch away for the full duration to trigger a lock.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text("Global setting: The timer counts total elapsed time since unlock, regardless of whether you're actively using the app.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else {
                    let globalTimeout = SessionManager.shared.sessionTimeout / 60
                    let timeString = globalTimeout == 0 ? "Immediately" : (globalTimeout == FGConstants.indefiniteSliderValue ? "Never" : "\(Int(globalTimeout)) min")
                    Text("Using Global Timer (\(timeString))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
            .padding()
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let activeApp = lockedAppsManager.lockedApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                if let custom = activeApp.customSessionTimeout {
                    hasCustomTimer = true
                    customTimeoutMinutes = custom == FGConstants.indefiniteSessionValue ? FGConstants.indefiniteSliderValue : custom / 60
                } else {
                    hasCustomTimer = false
                    let lastSelection = UserDefaults.standard.double(forKey: "lastCustomTimeout_\(app.bundleIdentifier)")
                    customTimeoutMinutes = lastSelection > 0 ? lastSelection : 5
                }
                if let mode = activeApp.timerFromFocus {
                    appTimerMode = mode ? 2 : 1
                } else {
                    appTimerMode = 0
                }
            }
        }
        .onChangeCompat(of: hasCustomTimer) { newValue in
            saveChanges(hasCustom: newValue, minutes: customTimeoutMinutes)
        }
        .onChangeCompat(of: customTimeoutMinutes) { newValue in
            saveChanges(hasCustom: hasCustomTimer, minutes: newValue)
        }
        .onChangeCompat(of: appTimerMode) { newValue in
            let fromFocus: Bool?
            switch newValue {
            case 1: fromFocus = false
            case 2: fromFocus = true
            default: fromFocus = nil
            }
            lockedAppsManager.updateTimerFromFocus(for: app.bundleIdentifier, fromFocus: fromFocus)
            SessionManager.shared.refreshSessionForTimerMode(app.bundleIdentifier)
        }
    }
    
    private func saveChanges(hasCustom: Bool, minutes: Double) {
        let timeout: TimeInterval? = hasCustom ? (minutes == FGConstants.indefiniteSliderValue ? FGConstants.indefiniteSessionValue : minutes * 60) : nil
        lockedAppsManager.updateCustomSessionTimeout(for: app.bundleIdentifier, timeout: timeout)
        if hasCustom {
            UserDefaults.standard.set(minutes, forKey: "lastCustomTimeout_\(app.bundleIdentifier)")
        }
        SessionManager.shared.revokeSession(for: app.bundleIdentifier)
    }
}
