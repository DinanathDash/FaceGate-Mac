import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case lockedApps = "Locked Apps"
    case authentication = "Authentication"
    case behavior = "Behavior"
    case about = "About"

    var id: String { rawValue }

    var title: String { rawValue }

    var systemImage: String {
        switch self {
        case .lockedApps: return "lock.app.dashed"
        case .authentication: return "person.badge.key.fill"
        case .behavior: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - Navigation State

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selectedTab: SettingsTab? = {
        if let raw = UserDefaults.standard.string(forKey: "lastSelectedSettingsTab"),
           let tab = SettingsTab(rawValue: raw) {
            return tab
        }
        return .lockedApps
    }() {
        didSet {
            if let value = selectedTab?.rawValue {
                UserDefaults.standard.set(value, forKey: "lastSelectedSettingsTab")
            }
        }
    }
    private init() {}
}

// MARK: - Main Settings View

struct ModernSettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var navigationHistory: [SettingsTab] = [.lockedApps]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    private var activeTab: SettingsTab {
        navigation.selectedTab ?? .lockedApps
    }

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebarView(selectedTab: $navigation.selectedTab)
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: 220,
                    max: 260
                )
        } detail: {
            SettingsDetailView(tab: activeTab)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.prominentDetail)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                    
                    Button { goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                }
                .controlGroupStyle(.navigation)
            }
        }
        .onChangeCompat(of: navigation.selectedTab) { _ in recordNavigation() }
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: "lastSelectedSettingsTab"),
               let tab = SettingsTab(rawValue: raw) {
                navigation.selectedTab = tab
            }
        }
    }

    private var canGoBack: Bool { historyIndex > 0 }
    private var canGoForward: Bool { historyIndex < navigationHistory.count - 1 }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation else { return }
        guard let tab = navigation.selectedTab else { return }
        if navigationHistory.last == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

// MARK: - Sidebar

private struct SettingsSidebarView: View {
    @Binding var selectedTab: SettingsTab?
    @State private var showPermissions = false
    @State private var showResetConfirmation = false
    @State private var showThemePicker = false
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    
    private var currentTheme: AppTheme {
        get { AppTheme(rawValue: currentThemeRaw) ?? .classic }
        set { currentThemeRaw = newValue.rawValue }
    }

    var body: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyleSoftIfAvailable()
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: { showThemePicker = true }) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .help("Toggle Theme (\(currentTheme.rawValue))")
                
                Button(action: { showPermissions = true }) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .help("Permissions")
                
                Button(action: { showResetConfirmation = true }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .help("Reset App")

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showThemePicker) {
            ThemePickerView()
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsDialogView()
        }
        .alert("Reset App", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetApp()
            }
        } message: {
            Text("Are you sure you want to completely reset FaceGate? This will delete all settings and enrolled faces, and the app will restart.")
        }
    }
    
    private func resetApp() {
        Task {
            // Unregister from login items
            try? await SMAppService.mainApp.unregister()
            
            try? FaceDataStore.shared.delete()
            let bundleId = Bundle.main.bundleIdentifier ?? "com.dweep.FaceGate"
            
            // Reset system permissions (Accessibility, Camera, etc)
            let tccProcess = Process()
            tccProcess.launchPath = "/usr/bin/tccutil"
            tccProcess.arguments = ["reset", "All", bundleId]
            try? tccProcess.run()
            tccProcess.waitUntilExit()
            
            // Clear defaults
            let process = Process()
            process.launchPath = "/usr/bin/defaults"
            process.arguments = ["delete", bundleId]
            try? process.run()
            process.waitUntilExit()
            
            await MainActor.run {
                let restartProcess = Process()
                restartProcess.launchPath = "/usr/bin/open"
                restartProcess.arguments = ["-n", Bundle.main.bundlePath]
                try? restartProcess.run()
                exit(0)
            }
        }
    }
}

// MARK: - Permissions Dialog

struct PermissionsDialogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var isResetting = false
    @State private var resetSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            
            Text("FaceGate needs these permissions to protect your apps.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required to monitor and block app launches")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Camera")
                            .font(.system(size: 13, weight: .medium))
                        Text("Required for Face Unlock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Auto")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
            
            HStack(spacing: 16) {
                if resetSuccess {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Restarting to apply...")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                } else {
                    Button(isResetting ? "Resetting..." : "Reset") {
                        isResetting = true
                        Task {
                            let process = Process()
                            process.launchPath = "/usr/bin/tccutil"
                            process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.dweep.FaceGate"]
                            try? process.run()
                            process.waitUntilExit()
                            
                            await MainActor.run {
                                resetSuccess = true
                            }
                            
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            
                            await MainActor.run {
                                let restartProcess = Process()
                                restartProcess.launchPath = "/usr/bin/open"
                                restartProcess.arguments = ["-n", Bundle.main.bundlePath]
                                try? restartProcess.run()
                                exit(0)
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isResetting)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
        .task {
            while !Task.isCancelled {
                await MainActor.run {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
                    let isTrusted = AXIsProcessTrustedWithOptions(options)
                    if accessibilityGranted != isTrusted {
                        accessibilityGranted = isTrusted
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

// MARK: - Detail Router

private struct SettingsDetailView: View {
    let tab: SettingsTab

    var body: some View {
        Group {
            switch tab {
            case .lockedApps:
                ModernLockedAppsSettingsView()
            case .authentication: AuthSettingsView()
            case .behavior: BehaviorSettingsView()
            case .about: AboutView()
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}

// MARK: - Auth Settings

struct AuthSettingsView: View {
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    private var currentTheme: AppTheme { AppTheme(rawValue: currentThemeRaw) ?? .classic }
    
    @State private var faceUnlockEnabled = UserDefaults.standard.bool(forKey: FGConstants.faceUnlockEnabledKey)
    @State private var faceEnrolled = UserDefaults.standard.bool(forKey: FGConstants.faceEnrolledKey)
    @State private var touchIDEnabled = TouchIDAuth.shared.isEnabled
    @State private var isTouchIDAvailable = TouchIDAuth.shared.isAvailable
    @State private var primaryAuthOption = UserDefaults.standard.string(forKey: FGConstants.primaryAuthOptionKey) ?? "face"
    @State private var showChangePassword = false
    @State private var showFaceEnrollment = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var passwordSuccess = false
    @State private var faceThreshold: Float = {
        let stored = UserDefaults.standard.float(forKey: FGConstants.faceUnlockThresholdKey)
        return stored > 0 ? stored : FGConstants.defaultFaceUnlockThreshold
    }()
    @State private var enrolledFaces: [FaceEnrollment.EnrolledFace] = []
    @State private var isAddingFace = false
    @State private var faceNames: [UUID: String] = [:]
    var body: some View {
        Form {
            // MARK: Face Unlock Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "faceid")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                                .frame(width: 24, alignment: .center)
                            VStack(alignment: .leading) {
                                Text("Face Unlock")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(faceEnrolled ? "Face enrolled and ready" : "No face enrolled yet")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 2)

                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            if faceEnrolled {
                                Toggle("", isOn: $faceUnlockEnabled)
                                    .labelsHidden()
                                    .onChangeCompat(of: faceUnlockEnabled) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: FGConstants.faceUnlockEnabledKey)
                                        if !newValue && primaryAuthOption == "face" {
                                            primaryAuthOption = isTouchIDAvailable ? "touchid" : "password"
                                            UserDefaults.standard.set(primaryAuthOption, forKey: FGConstants.primaryAuthOptionKey)
                                        }
                                    }
                            } else {
                                Button("Enroll Face") {
                                    isAddingFace = false
                                    showFaceEnrollment = true
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    // Enrolled Faces list
                    if faceEnrolled {
                        if currentTheme == .classic {
                            ClassicFaceList(
                                enrolledFaces: $enrolledFaces,
                                faceNames: $faceNames,
                                renameFace: renameFace,
                                deleteFace: deleteFace,
                                deleteAllFaceData: {
                                    try? FaceDataStore.shared.delete()
                                    DispatchQueue.main.async {
                                        enrolledFaces = []
                                        faceEnrolled = false
                                        faceNames.removeAll()
                                        if primaryAuthOption == "face" {
                                            primaryAuthOption = isTouchIDAvailable ? "touchid" : "password"
                                            UserDefaults.standard.set(primaryAuthOption, forKey: FGConstants.primaryAuthOptionKey)
                                        }
                                    }
                                },
                                showFaceEnrollment: $showFaceEnrollment,
                                isAddingFace: $isAddingFace
                            )
                        } else {
                            ModernFaceList(
                                enrolledFaces: $enrolledFaces,
                                faceNames: $faceNames,
                                renameFace: renameFace,
                                deleteFace: deleteFace,
                                deleteAllFaceData: {
                                    try? FaceDataStore.shared.delete()
                                    DispatchQueue.main.async {
                                        enrolledFaces = []
                                        faceEnrolled = false
                                        faceNames.removeAll()
                                        if primaryAuthOption == "face" {
                                            primaryAuthOption = isTouchIDAvailable ? "touchid" : "password"
                                            UserDefaults.standard.set(primaryAuthOption, forKey: FGConstants.primaryAuthOptionKey)
                                        }
                                    }
                                },
                                showFaceEnrollment: $showFaceEnrollment,
                                isAddingFace: $isAddingFace
                            )
                        }
                    }

                    // Action buttons
                    if faceEnrolled {
                        HStack {
                            Spacer()
                            
                            Button("Re-enroll Fresh") {
                                isAddingFace = false
                                showFaceEnrollment = true
                            }
                            .controlSize(.small)

                            Button("Delete All Face Data") {
                                try? FaceDataStore.shared.delete()
                                refreshEnrolledFaces()
                                if primaryAuthOption == "face" {
                                    primaryAuthOption = isTouchIDAvailable ? "touchid" : "password"
                                    UserDefaults.standard.set(primaryAuthOption, forKey: FGConstants.primaryAuthOptionKey)
                                }
                            }
                            .controlSize(.small)
                            .foregroundColor(.red)
                        }
                    }

                    // Sensitivity slider (only shown if enrolled).
                    if faceEnrolled {
                        Divider()
                            .padding(.vertical, 4)
                            
                        VStack(alignment: .leading, spacing: 8) {
                            if currentTheme == .classic {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Sensitivity")
                                            .font(.system(size: 12))
                                        Spacer()
                                        Text(sensitivityLabel)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $faceThreshold, in: 0.4...0.9, step: 0.05)
                                        .onChangeCompat(of: faceThreshold) { newValue in
                                            AuthenticationManager.shared.faceAuthManager.updateThreshold(newValue)
                                        }
                                    Text("Higher sensitivity requires a closer match. Lower is more permissive.")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                            } else {
                                HStack(alignment: .top) {
                                    Text("Sensitivity")
                                        .font(.system(size: 13))
                                        .padding(.top, 3)
                                    Spacer()
                                    VStack(spacing: 2) {
                                        Slider(value: $faceThreshold, in: 0.4...0.9, step: 0.05)
                                            .onChangeCompat(of: faceThreshold) { newValue in
                                                AuthenticationManager.shared.faceAuthManager.updateThreshold(newValue)
                                            }
                                            .labelsHidden()
                                        
                                        HStack {
                                            Text("Permissive")
                                            Spacer()
                                            Text("Strict")
                                        }
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                    }
                                    .frame(width: 220)
                                }
                                
                                Text("Higher sensitivity requires a closer match. Lower is more permissive.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                        .disabled(!faceUnlockEnabled)
                    }

                    // Divider and Primary Auth Option
                    Divider()
                        .padding(.vertical, 4)
                        
                    HStack {
                        Text("Default Authentication")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $primaryAuthOption) {
                            if faceEnrolled && faceUnlockEnabled {
                                Text("Face Unlock").tag("face")
                            }
                            Text("Touch ID").tag("touchid")
                            Text("Password").tag("password")
                        }
                        .frame(width: 150)
                        .onChangeCompat(of: primaryAuthOption) { newValue in
                            UserDefaults.standard.set(newValue, forKey: FGConstants.primaryAuthOptionKey)
                        }
                    }
                }
            } header: {
                Text("Primary")
            }

            // MARK: Touch ID Section
            Section {
                // Camera picker (visible only when multiple cameras are available).
                CameraPickerView()
            } header: {
                Text("Camera")
            }

            Section {
                Toggle(isOn: $touchIDEnabled) {
                    HStack {
                        Image(systemName: "touchid")
                            .font(.system(size: 18))
                            .foregroundColor(.pink)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading) {
                            Text("Touch ID")
                                .font(.system(size: 13, weight: .medium))
                            Text(isTouchIDAvailable ? "Available on this Mac" : "Not available on this Mac")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(!isTouchIDAvailable)
                .onChangeCompat(of: touchIDEnabled) { newValue in
                    TouchIDAuth.shared.isEnabled = newValue
                }
            } header: {
                Text("Fallbacks")
            }

            // MARK: Password Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                            .frame(width: 24, alignment: .center)
                        VStack(alignment: .leading) {
                            Text("App Password")
                                .font(.system(size: 13, weight: .medium))
                            Text(PasswordAuth.shared.isPasswordSet ? "Password is set" : "No password set")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Change") {
                            showChangePassword.toggle()
                        }
                    }

                    if showChangePassword {
                        VStack(alignment: .leading, spacing: 8) {
                            if PasswordAuth.shared.isPasswordSet {
                                LabeledContent("Current password") {
                                    SecureField("", text: $oldPassword)
                                        .labelsHidden()
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            LabeledContent("New password") {
                                SecureField("", text: $newPassword)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.leading)
                            }
                            LabeledContent("Confirm new password") {
                                SecureField("", text: $confirmPassword)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            PasswordStrengthView(password: newPassword)

                            if let error = passwordError {
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }

                            if passwordSuccess {
                                Text("Password changed successfully!")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                            }

                            HStack {
                                Button("Cancel") {
                                    resetPasswordFields()
                                }
                                Button("Save") {
                                    changePassword()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.leading, 24)
                    }
                }
            }

            // MARK: Security Disclaimer
            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text("Face Unlock uses your Mac's built-in camera for convenience-level authentication. It is not equivalent to Apple's Face ID and may be susceptible to photo-based spoofing. For high security, use Touch ID or your app password.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Security Notice")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            refreshEnrolledFaces()
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .sheet(isPresented: $showFaceEnrollment) {
            FaceEnrollmentView(
                onComplete: {
                    showFaceEnrollment = false
                    refreshEnrolledFaces()
                },
                isInSettings: true,
                isAddingFace: isAddingFace
            )
        }
    }

    private var sensitivityLabel: String {
        if faceThreshold < 0.5 {
            return "Very Permissive"
        } else if faceThreshold < 0.6 {
            return "Permissive"
        } else if faceThreshold < 0.7 {
            return "Balanced"
        } else if faceThreshold < 0.8 {
            return "Strict"
        } else {
            return "Very Strict"
        }
    }

    private func changePassword() {
        passwordError = nil
        passwordSuccess = false

        guard !newPassword.isEmpty else {
            passwordError = "Password cannot be empty"
            return
        }
        guard newPassword.count >= 6 else {
            passwordError = "Password must be at least 6 characters"
            return
        }
        let hasUpper = newPassword.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil
        let hasLower = newPassword.rangeOfCharacter(from: CharacterSet.lowercaseLetters) != nil
        let hasNumber = newPassword.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
        let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?\\")
        let hasSpecial = newPassword.rangeOfCharacter(from: specialChars) != nil
        
        guard hasUpper && hasLower && hasNumber && hasSpecial else {
            passwordError = "Password must meet all strength criteria"
            return
        }
        guard newPassword == confirmPassword else {
            passwordError = "Passwords don't match"
            return
        }

        if PasswordAuth.shared.isPasswordSet {
            guard PasswordAuth.shared.changePassword(from: oldPassword, to: newPassword) else {
                passwordError = "Current password is incorrect"
                return
            }
        } else {
            do {
                try PasswordAuth.shared.setPassword(newPassword)
            } catch {
                passwordError = "Failed to save password: \(error.localizedDescription)"
                return
            }
        }

        passwordSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            resetPasswordFields()
        }
    }

    private func resetPasswordFields() {
        showChangePassword = false
        oldPassword = ""
        newPassword = ""
        confirmPassword = ""
        passwordError = nil
        passwordSuccess = false
    }

    private func refreshEnrolledFaces() {
        faceEnrolled = UserDefaults.standard.bool(forKey: FGConstants.faceEnrolledKey)
        faceUnlockEnabled = UserDefaults.standard.bool(forKey: FGConstants.faceUnlockEnabledKey)
        if let enrollment = FaceDataStore.shared.load() {
            enrolledFaces = enrollment.faces
            for face in enrollment.faces {
                if faceNames[face.id] == nil {
                    faceNames[face.id] = face.name
                }
            }
        } else {
            enrolledFaces = []
            faceNames = [:]
        }
        
        if primaryAuthOption == "face" && (!faceEnrolled || !faceUnlockEnabled) {
            primaryAuthOption = isTouchIDAvailable ? "touchid" : "password"
            UserDefaults.standard.set(primaryAuthOption, forKey: FGConstants.primaryAuthOptionKey)
        }
    }

    private func renameFace(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if let enrollment = FaceDataStore.shared.load(),
               let index = enrollment.faces.firstIndex(where: { $0.id == id }) {
                faceNames[id] = enrollment.faces[index].name
            }
            return
        }
        if var enrollment = FaceDataStore.shared.load() {
            if let index = enrollment.faces.firstIndex(where: { $0.id == id }) {
                enrollment.faces[index].name = trimmed
                try? FaceDataStore.shared.save(enrollment)
                faceNames[id] = trimmed
                refreshEnrolledFaces()
            }
        }
    }

    private func deleteFace(id: UUID) {
        if var enrollment = FaceDataStore.shared.load() {
            enrollment.faces.removeAll(where: { $0.id == id })
            faceNames.removeValue(forKey: id)  // clean up stale buffer entry
            if enrollment.faces.isEmpty {
                try? FaceDataStore.shared.delete()
            } else {
                try? FaceDataStore.shared.save(enrollment)
            }
            refreshEnrolledFaces()
        }
    }
}

// MARK: - Behavior Settings

struct BehaviorSettingsView: View {
    @AppStorage(FGConstants.launchAtLoginKey) private var launchAtLogin = false
    @AppStorage(FGConstants.lockOnSleepKey) private var lockOnSleep = false
    @State private var sessionTimeoutMinutes: Double = FGConstants.defaultSessionTimeout / 60
    @State private var uninstallProtection = UserDefaults.standard.bool(forKey: FGConstants.uninstallProtectionKey)
    @State private var isUpdatingUninstallProtection = false

    @AppStorage(FGConstants.emergencyKillEnabledKey) private var emergencyKillEnabled = true
    @AppStorage(FGConstants.emergencyKillModifierKey) private var emergencyKillModifier = "Command"
    @AppStorage(FGConstants.emergencyKillTriggerKey) private var emergencyKillKey = "`"

    @AppStorage(FGConstants.sessionTimerFromFocusKey) private var sessionTimerFromFocus = false

    @AppStorage(FGConstants.disableFaceUnlockHoursKey) private var disableFaceUnlockHours = false
    @AppStorage(FGConstants.faceUnlockDisabledStartHourKey) private var startHour = 22
    @AppStorage(FGConstants.faceUnlockDisabledStartMinuteKey) private var startMinute = 0
    @AppStorage(FGConstants.faceUnlockDisabledEndHourKey) private var endHour = 7
    @AppStorage(FGConstants.faceUnlockDisabledEndMinuteKey) private var endMinute = 0

    private var startTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let calendar = Calendar.current
                var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                comps.hour = startHour
                comps.minute = startMinute
                return calendar.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                startHour = comps.hour ?? 22
                startMinute = comps.minute ?? 0
            }
        )
    }

    private var endTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let calendar = Calendar.current
                var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                comps.hour = endHour
                comps.minute = endMinute
                return calendar.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                endHour = comps.hour ?? 7
                endMinute = comps.minute ?? 0
            }
        )
    }

    // Lock all apps schedule
    @AppStorage(FGConstants.lockAllScheduleEnabledKey) private var lockScheduleEnabled = false
    @AppStorage(FGConstants.lockAllStartHourKey) private var lockStartHour = 22
    @AppStorage(FGConstants.lockAllStartMinuteKey) private var lockStartMinute = 0
    @AppStorage(FGConstants.lockAllEndHourKey) private var lockEndHour = 7
    @AppStorage(FGConstants.lockAllEndMinuteKey) private var lockEndMinute = 0

    @State private var lockStartTime = Date()
    @State private var lockEndTime = Date()

    // Unlock all apps schedule
    @AppStorage(FGConstants.unlockAllScheduleEnabledKey) private var unlockScheduleEnabled = false
    @AppStorage(FGConstants.unlockAllStartHourKey) private var unlockStartHour = 7
    @AppStorage(FGConstants.unlockAllStartMinuteKey) private var unlockStartMinute = 0
    @AppStorage(FGConstants.unlockAllEndHourKey) private var unlockEndHour = 22
    @AppStorage(FGConstants.unlockAllEndMinuteKey) private var unlockEndMinute = 0

    @State private var unlockStartTime = Date()
    @State private var unlockEndTime = Date()

    @ObservedObject private var scheduleManager = AppScheduleManager.shared

    private var shortcutModifierSymbol: String {
        emergencyKillModifier == "Command" ? "⌘" : "⇧"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch FaceGate at Login", isOn: $launchAtLogin)
                    .onChangeCompat(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            } header: {
                Text("Startup")
            }

            Section {
                Toggle("App Deletion Protection (highly recommended)", isOn: Binding(
                    get: { uninstallProtection },
                    set: { newValue in
                        guard newValue != uninstallProtection, !isUpdatingUninstallProtection else { return }
                        setUninstallProtection(newValue)
                    }
                ))
                .disabled(isUpdatingUninstallProtection)
                Text("Changing this setting requires administrator authentication. When enabled, FaceGate is protected from deletion to safeguard your locked applications.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } header: {
                Text("Uninstall Protection")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session Timeout")
                            .font(.system(size: 13))
                        Spacer(minLength: 16)
                        Picker("", selection: Binding(
                            get: { sessionTimeoutMinutes },
                            set: { newValue in
                                sessionTimeoutMinutes = newValue
                                let timeout: TimeInterval = newValue == FGConstants.indefiniteSliderValue ? FGConstants.indefiniteSessionValue : newValue * 60
                                SessionManager.shared.setSessionTimeout(timeout)
                            }
                        )) {
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
                    Text("After unlocking an app, it stays unlocked for this duration before re-locking. Set to Immediately to lock immediately after use, or Never to keep unlocked until you manually lock from the menu bar.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if sessionTimeoutMinutes > 0 && sessionTimeoutMinutes < FGConstants.indefiniteSliderValue {
                        Picker("Timer Mode", selection: $sessionTimerFromFocus) {
                            Text("From last unlock").tag(false)
                            Text("From when app loses focus").tag(true)
                        }
                        .pickerStyle(.menu)
                        if sessionTimerFromFocus {
                            Text("The timer only counts down while the app is not in focus. Switch away for the full duration to trigger a lock.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("The timer counts total elapsed time since unlock, regardless of whether you're actively using the app.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Locking")
            }

            Section {
                Toggle(isOn: $lockOnSleep) {
                    Text("Lock all apps when Mac sleeps or locks")
                }
                .toggleStyle(.checkbox)
                if lockOnSleep {
                    Text("All active unlock sessions will be revoked when the Mac goes to sleep, the display sleeps, or the screen is locked. This overrides app timers and indefinite unlock.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Section {
                HStack(spacing: 4) {
                    Toggle(isOn: $lockScheduleEnabled) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .onChangeCompat(of: lockScheduleEnabled) { newValue in
                            scheduleManager.lockScheduleEnabled = newValue
                            scheduleManager.refresh()
                        }

                    HStack {
                        Text("Lock all apps between")

                        DatePicker("", selection: $lockStartTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .onChangeCompat(of: lockStartTime) { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                lockStartHour = comps.hour ?? 22
                                lockStartMinute = comps.minute ?? 0
                                scheduleManager.lockStartHour = lockStartHour
                                scheduleManager.lockStartMinute = lockStartMinute
                                scheduleManager.refresh()
                            }

                        Text("and")

                        DatePicker("", selection: $lockEndTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .onChangeCompat(of: lockEndTime) { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                lockEndHour = comps.hour ?? 7
                                lockEndMinute = comps.minute ?? 0
                                scheduleManager.lockEndHour = lockEndHour
                                scheduleManager.lockEndMinute = lockEndMinute
                                scheduleManager.refresh()
                            }
                    }
                    .disabled(!lockScheduleEnabled)
                    .opacity(lockScheduleEnabled ? 1 : 0.5)
                }

                if lockScheduleEnabled {
                    Text("All locked apps will be automatically locked during these hours. Manually unlocked apps are not affected.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if scheduleManager.lockUnlockWindowsOverlap {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Lock and unlock windows overlap. Lock takes priority - unlock will be skipped during the overlap.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack(spacing: 4) {
                    Toggle(isOn: $unlockScheduleEnabled) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .onChangeCompat(of: unlockScheduleEnabled) { newValue in
                            scheduleManager.unlockScheduleEnabled = newValue
                            scheduleManager.refresh()
                        }

                    HStack {
                        Text("Unlock all apps between")

                        DatePicker("", selection: $unlockStartTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .onChangeCompat(of: unlockStartTime) { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                unlockStartHour = comps.hour ?? 7
                                unlockStartMinute = comps.minute ?? 0
                                scheduleManager.unlockStartHour = unlockStartHour
                                scheduleManager.unlockStartMinute = unlockStartMinute
                                scheduleManager.refresh()
                            }

                        Text("and")

                        DatePicker("", selection: $unlockEndTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                            .labelsHidden()
                            .onChangeCompat(of: unlockEndTime) { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                unlockEndHour = comps.hour ?? 22
                                unlockEndMinute = comps.minute ?? 0
                                scheduleManager.unlockEndHour = unlockEndHour
                                scheduleManager.unlockEndMinute = unlockEndMinute
                                scheduleManager.refresh()
                            }
                    }
                    .disabled(!unlockScheduleEnabled)
                    .opacity(unlockScheduleEnabled ? 1 : 0.5)
                }

                if unlockScheduleEnabled {
                    Text("All locked apps will be automatically unlocked during these hours. Manually locked apps are not affected.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if scheduleManager.lockUnlockWindowsOverlap {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Lock and unlock windows overlap. Lock takes priority - unlock will be skipped during the overlap.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Toggle("Disable Face Unlock during certain hours", isOn: $disableFaceUnlockHours)
                    .onChangeCompat(of: disableFaceUnlockHours) { newValue in
                        if newValue {
                            // Ensure start/end hours are written to UserDefaults immediately so that FaceAuthManager has them
                            UserDefaults.standard.set(startHour, forKey: FGConstants.faceUnlockDisabledStartHourKey)
                            UserDefaults.standard.set(startMinute, forKey: FGConstants.faceUnlockDisabledStartMinuteKey)
                            UserDefaults.standard.set(endHour, forKey: FGConstants.faceUnlockDisabledEndHourKey)
                            UserDefaults.standard.set(endMinute, forKey: FGConstants.faceUnlockDisabledEndMinuteKey)
                        }
                    }
                
                if disableFaceUnlockHours {
                    HStack {
                        DatePicker("Start Time", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                        
                        Spacer()
                        
                        DatePicker("End Time", selection: endTimeBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.stepperField)
                    }
                    
                    Text("During these hours, App Lock remains active but face recognition is bypassed, forcing password/Touch ID entry.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Face Unlock Schedule")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Emergency Kill Shortcut")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Toggle(isOn: $emergencyKillEnabled) { EmptyView() }
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .accessibilityLabel("Enable Emergency Kill Shortcut")
                            .onChangeCompat(of: emergencyKillEnabled) { _ in
                                GlobalHotkeyManager.shared.reRegisterShortcut()
                            }
                    }
                    
                    if emergencyKillEnabled {
                    HStack {
                        Text("Compulsory modifiers:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("⌃ Control + ⌥ Option")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }
                    
                    HStack(spacing: 8) {
                        Text("Third Modifier:")
                            .font(.system(size: 11))
                        Picker("", selection: $emergencyKillModifier) {
                            Text("⌘ Command").tag("Command")
                            Text("⇧ Shift").tag("Shift")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)
                        .onChangeCompat(of: emergencyKillModifier) { _ in
                            GlobalHotkeyManager.shared.reRegisterShortcut()
                        }

                        Text("Key:")
                            .font(.system(size: 11))
                        Picker("", selection: $emergencyKillKey) {
                            Text("` (Backtick)").tag("`")
                            Text("Escape").tag("Escape")
                            Text("Space").tag("Space")
                            Text("Q").tag("Q")
                            Text("K").tag("K")
                            Text("X").tag("X")
                            Text("Delete").tag("Delete")
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 130)
                        .onChangeCompat(of: emergencyKillKey) { _ in
                            GlobalHotkeyManager.shared.reRegisterShortcut()
                        }
                    }
                    
                    Text("Current Shortcut: ⌃⌥\(shortcutModifierSymbol)\(emergencyKillKey)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.blue)
                    
                    Text("Pressing the shortcut above at any time will instantly quit FaceGate without requiring authentication.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Emergency")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .onAppear {
            // Sync uninstall protection state
            let currentStatus = getActualProtectionState()
            uninstallProtection = currentStatus
            UserDefaults.standard.set(currentStatus, forKey: FGConstants.uninstallProtectionKey)

            let storedTimeout = SessionManager.shared.sessionTimeout
            sessionTimeoutMinutes = storedTimeout == FGConstants.indefiniteSessionValue ? FGConstants.indefiniteSliderValue : storedTimeout / 60

            let calendar = Calendar.current
            let now = Date()



            // Load lock-all schedule dates
            var lockStartComponents = calendar.dateComponents([.year, .month, .day], from: now)
            lockStartComponents.hour = lockStartHour
            lockStartComponents.minute = lockStartMinute
            if let startDate = calendar.date(from: lockStartComponents) {
                lockStartTime = startDate
            }

            var lockEndComponents = calendar.dateComponents([.year, .month, .day], from: now)
            lockEndComponents.hour = lockEndHour
            lockEndComponents.minute = lockEndMinute
            if let endDate = calendar.date(from: lockEndComponents) {
                lockEndTime = endDate
            }

            // Load unlock-all schedule dates
            var unlockStartComponents = calendar.dateComponents([.year, .month, .day], from: now)
            unlockStartComponents.hour = unlockStartHour
            unlockStartComponents.minute = unlockStartMinute
            if let startDate = calendar.date(from: unlockStartComponents) {
                unlockStartTime = startDate
            }

            var unlockEndComponents = calendar.dateComponents([.year, .month, .day], from: now)
            unlockEndComponents.hour = unlockEndHour
            unlockEndComponents.minute = unlockEndMinute
            if let endDate = calendar.date(from: unlockEndComponents) {
                unlockEndTime = endDate
            }

            // Sync local AppStorage settings to scheduleManager on appear
            scheduleManager.lockScheduleEnabled = lockScheduleEnabled
            scheduleManager.lockStartHour = lockStartHour
            scheduleManager.lockStartMinute = lockStartMinute
            scheduleManager.lockEndHour = lockEndHour
            scheduleManager.lockEndMinute = lockEndMinute

            scheduleManager.unlockScheduleEnabled = unlockScheduleEnabled
            scheduleManager.unlockStartHour = unlockStartHour
            scheduleManager.unlockStartMinute = unlockStartMinute
            scheduleManager.unlockEndHour = unlockEndHour
            scheduleManager.unlockEndMinute = unlockEndMinute

            scheduleManager.refresh()
        }
        .onChangeCompat(of: sessionTimerFromFocus) { _ in
            for bundleId in SessionManager.shared.activeSessions.keys {
                SessionManager.shared.refreshSessionForTimerMode(bundleId)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
            }
        }
    }

    private var protectionTargetPath: String {
        let installedPath = "/Applications/FaceGate.app"
        if FileManager.default.fileExists(atPath: installedPath) {
            return installedPath
        }
        return Bundle.main.bundlePath
    }

    private func getActualProtectionState() -> Bool {
        let bundlePath = protectionTargetPath
        let bundleURL = URL(fileURLWithPath: bundlePath)
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: bundlePath)
            let ownerName = attrs[.ownerAccountName] as? String
            
            let resourceValues = try bundleURL.resourceValues(forKeys: [.isUserImmutableKey])
            let isImmutable = resourceValues.isUserImmutable ?? false
            
            return ownerName == "root" || isImmutable
        } catch {
            return false
        }
    }

    private func setUninstallProtection(_ enabled: Bool) {
        guard !isUpdatingUninstallProtection else { return }
        isUpdatingUninstallProtection = true
        
        let bundlePath = protectionTargetPath
        let escapedPath = bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        
        let command: String
        if enabled {
            command = "chown -R root:wheel '\(escapedPath)' && chflags -R uchg '\(escapedPath)'"
        } else {
            let username = NSUserName()
            command = "chflags -R nouchg '\(escapedPath)' && chown -R \(username):staff '\(escapedPath)'"
        }
        
        let source = "do shell script \"\(command)\" with administrator privileges with prompt \"FaceGate wants to make changes.\""
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("[FaceGate] Uninstall protection failed: \(error)")
                    self.uninstallProtection = self.getActualProtectionState()
                } else {
                    UserDefaults.standard.set(enabled, forKey: FGConstants.uninstallProtectionKey)
                    self.uninstallProtection = enabled
                }
                self.isUpdatingUninstallProtection = false
            }
        }
    }
    
}

// MARK: - About View

struct ClassicAboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 6) {
                    Text("FaceGate")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Text("A privacy-focused app locker for macOS with face authentication.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                Divider()
                    .frame(maxWidth: 240)
                    .padding(.vertical, 4)

                VStack(spacing: 8) {
                    Text("⚠️ Security Disclaimer")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Face Unlock is a convenience feature using the built-in camera. It is NOT equivalent to Apple's Face ID and may be susceptible to photo-based spoofing. For maximum security, use Touch ID or the app password.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 350)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.1))
                )
                
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://github.com/dweep-desai/FaceGate-Mac")!) {
                        HStack(spacing: 8) {
                            Image("GitHubIcon")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                                .foregroundColor(.primary)
                            Text("GitHub Repository")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(width: 200, height: 28)
                    }
                    .buttonStyle(.link)

                    Link(destination: URL(string: "https://github.com/sponsors/dweep-desai")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .foregroundColor(.pink)
                            Text("Sponsor on GitHub")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(width: 200, height: 28)
                    }
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)

                VStack(spacing: 4) {
                    Text("Open Source - MIT License")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("© 2026 Dweep Desai")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            .padding(.top, 48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }
}

struct ModernAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About FaceGate")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                        
                    GroupBox {
                        HStack(alignment: .center, spacing: 16) {
                            if let appIcon = NSApp.applicationIconImage {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                            } else {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 64, height: 64)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("FaceGate")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("(v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                Text("A privacy-focused app locker for macOS with face authentication.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Security Disclaimer")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                        
                    HStack {
                        Text("Face Unlock is a convenience feature using the built-in camera. It is NOT equivalent to Apple's Face ID and may be susceptible to photo-based spoofing. For maximum security, use Touch ID or the app password.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Community")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                        
                    HStack(spacing: 12) {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/dweep-desai/FaceGate-Mac")!)
                        } label: {
                            Label {
                                Text("GitHub Repository")
                            } icon: {
                                Image("GitHubIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/dweep-desai")!)
                        } label: {
                            Label("Sponsor on GitHub", systemImage: "heart.fill")
                                .foregroundColor(.pink)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                VStack(spacing: 4) {
                    Text("Open Source - MIT License")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("© 2026 Dweep Desai")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
            }
            .padding(32)
        }
    }
}

struct AboutView: View {
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue
    private var currentTheme: AppTheme { AppTheme(rawValue: currentThemeRaw) ?? .classic }
    
    var body: some View {
        if currentTheme == .classic {
            ClassicAboutView()
        } else {
            ModernAboutView()
        }
    }
}

// MARK: - LockedAppsSettingsView
struct LockedAppsSettingsView: View {
    var body: some View {
        ClassicLockedAppsSettingsView()
    }
}

// MARK: - Camera Picker

private struct CameraPickerView: View {
    @ObservedObject private var cameraManager = AuthenticationManager.shared.faceAuthManager.cameraManager
    @State private var selectedID: String = ""

    var body: some View {
        Picker(selection: $selectedID) {
            ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                HStack {
                    Image(systemName: camera.deviceType == .external ? "web.camera.fill" : "camera.fill")
                        .foregroundColor(.secondary)
                    Text(camera.localizedName)
                }
                .tag(camera.uniqueID)
            }
        } label: {
            HStack {
                Image(systemName: "video.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("Camera")
                        .font(.system(size: 13, weight: .medium))
                    Text(selectedCameraLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .disabled(cameraManager.availableCameras.count <= 1)
        .onAppear {
            cameraManager.refreshAvailableCameras()
            if selectedID.isEmpty {
                selectedID = cameraManager.selectedCameraID ?? cameraManager.availableCameras.first?.uniqueID ?? ""
            }
        }
        .onChangeCompat(of: selectedID) { newValue in
            cameraManager.selectedCameraID = newValue
        }
    }

    private var selectedCameraLabel: String {
        if let cam = cameraManager.availableCameras.first(where: { $0.uniqueID == selectedID }) {
            return cam.localizedName
        }
        return cameraManager.availableCameras.first?.localizedName ?? "No camera found"
    }
}

struct MacCenteredTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.alignment = .center
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.font = .systemFont(ofSize: 12)
        textField.focusRingType = .none
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacCenteredTextField
        var monitor: Any?
        
        init(_ parent: MacCenteredTextField) {
            self.parent = parent
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak textField] event in
                guard let tf = textField, let window = tf.window else { return event }
                let locationInWindow = event.locationInWindow
                let locationInView = tf.convert(locationInWindow, from: nil)
                if !tf.bounds.contains(locationInView) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
                parent.onCommit()
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = textView.string
                parent.onCommit()
                textView.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                textView.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}
