import SwiftUI
import ServiceManagement

/// First-run onboarding wizard.
/// Guides the user through: permissions → face enrollment → set password → select apps to lock.
struct SetupView: View {
    @State private var currentStep: SetupStep = .welcome
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordError: String?
    @State private var isPasswordSecure = true
    @State private var accessibilityGranted = false

    /// Called when setup is complete.
    var onSetupComplete: () -> Void

    /// Called when user chooses to open settings instead.
    var onOpenSettings: (() -> Void)?

    enum SetupStep: Int, CaseIterable {
        case welcome
        case permissions
        case faceEnrollment
        case setPassword
        case selectApps
        case complete
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
                
            // Step content.
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .permissions:
                    permissionsStep
                case .faceEnrollment:
                    faceEnrollmentStep
                case .setPassword:
                    passwordStep
                case .selectApps:
                    selectAppsStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 30)
            .padding(.bottom, 52)
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            // Progress indicator.
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(SetupStep.allCases, id: \.rawValue) { step in
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(.all)
        .frame(width: 500, height: 580)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image("WelcomeHeader")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 440, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 8) {
                Text("Welcome to FaceGate")
                    .font(.largeTitle.bold())

                Text("Lock your apps. Unlock with your face.")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "faceid", color: .blue, title: "Face Unlock", subtitle: "Just look at your camera to unlock apps")
                FeatureRow(icon: "touchid", color: .pink, title: "Touch ID", subtitle: "Use your fingerprint as a fallback")
                FeatureRow(icon: "key.fill", color: .orange, title: "App Password", subtitle: "Set a custom password for emergency access")
            }
            .padding(.horizontal, 40)
            .padding(.top, 4)

            Spacer(minLength: 0)

            setupButton("Get Started") {
                currentStep = .permissions
            }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 16) {
            ZStack {
                Image("PermissionsBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 440, height: 220)
                    .scaleEffect(1.2)
                
                Image("SettingsWindow")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 380)
                    .scaleEffect(1.4)
                    .offset(y: 100)
            }
            .frame(width: 440, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            VStack(spacing: 16) {
                Text("Permissions")
                    .font(.title.bold())

                Text("FaceGate needs these permissions to protect your apps.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                VStack(spacing: 16) {
                    PermissionRow(
                        icon: "hand.raised.fill",
                        title: "Accessibility",
                        description: "Required to monitor and block app launches",
                        isGranted: accessibilityGranted,
                        action: openAccessibilitySettings
                    )

                    PermissionRow(
                        icon: "camera.fill",
                        title: "Camera",
                        description: "Required for Face Unlock (granted on first use)",
                        isGranted: nil,
                        action: nil
                    )
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button("Back") { currentStep = .welcome }
                        .controlSize(.large)
                        .frame(minWidth: 120)
                        
                    setupButton("Continue") {
                        currentStep = .faceEnrollment
                    }
                }
            }
        }
        .onAppear {
            checkAccessibility()
        }
        .task {
            while !Task.isCancelled {
                if currentStep == .permissions {
                    await MainActor.run {
                        checkAccessibility()
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var faceEnrollmentStep: some View {
        VStack(spacing: 0) {
            FaceEnrollmentView(
                onComplete: {
                    currentStep = .setPassword
                },
                onBack: {
                    currentStep = .permissions
                },
                isInSettings: false
            )
        }
    }

    private var passwordStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Set App Password")
                .font(.title.bold())

            Text("This password is your emergency access method.\nYou'll use it if Face Unlock or Touch ID are unavailable.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            VStack(spacing: 8) {
                PasswordField(placeholder: "Choose a password", text: $password, isSecure: $isPasswordSecure)
                    .frame(maxWidth: 300)
                PasswordField(placeholder: "Confirm password", text: $confirmPassword, isSecure: $isPasswordSecure)
                    .frame(maxWidth: 300)

                PasswordStrengthView(password: password)
                    .frame(maxWidth: 300)

                if let error = passwordError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            
            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Back") { currentStep = .faceEnrollment }
                    .controlSize(.large)
                    .frame(minWidth: 120)

                setupButton("Set Password") {
                    savePassword()
                }
            }
        }
    }

    private var selectAppsStep: some View {
        VStack(spacing: 12) {
            Text("Select Apps to Lock")
                .font(.title.bold())

            Text("Choose which apps require authentication to open.")
                .font(.body)
                .foregroundColor(.secondary)

            AppPickerView()
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 40)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Back") { currentStep = .setPassword }
                    .controlSize(.large)
                    .frame(minWidth: 120)

                setupButton("Finish Setup") {
                    currentStep = .complete
                }
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer ()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            VStack(spacing: 4) {
                let faceEnrolled = UserDefaults.standard.bool(forKey: FGConstants.faceEnrolledKey)
                if faceEnrolled {
                    Text("Face Unlock enrolled and enabled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Face Unlock not enrolled (you can set it up later in Settings)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Text("FaceGate is now protecting your apps.\nLook for the shield icon in your menu bar.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 4) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Find me in the menu bar")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.15))
            )

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                setupButton("Start Protecting") {
                    finalizeSetup()
                    onSetupComplete()
                }
                Button("Configure Settings") {
                    finalizeSetup()
                    onOpenSettings?()
                }
                .buttonStyle(.link)
                .font(.body)
            }
        }
    }

    // MARK: - Helpers

    private func finalizeSetup() {
        UserDefaults.standard.set(true, forKey: FGConstants.setupCompletedKey)
        UserDefaults.standard.set(true, forKey: FGConstants.touchIDEnabledKey)
        UserDefaults.standard.set(true, forKey: FGConstants.launchAtLoginKey)
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to automatically register login item during setup: \(error)")
            }
        }
        for window in NSApp.windows {
            if window.title == "FaceGate Setup" {
                window.close()
            }
        }
    }

    private func setupButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minWidth: 120)
    }

    private func savePassword() {
        passwordError = nil
        guard !password.isEmpty else {
            passwordError = "Password cannot be empty"
            return
        }
        guard password.count >= 6 else {
            passwordError = "Password must be at least 6 characters"
            return
        }
        let hasUpper = password.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil
        let hasLower = password.rangeOfCharacter(from: CharacterSet.lowercaseLetters) != nil
        let hasNumber = password.rangeOfCharacter(from: CharacterSet.decimalDigits) != nil
        let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?\\")
        let hasSpecial = password.rangeOfCharacter(from: specialChars) != nil
        
        guard hasUpper && hasLower && hasNumber && hasSpecial else {
            passwordError = "Password must meet all strength criteria"
            return
        }
        guard password == confirmPassword else {
            passwordError = "Passwords don't match"
            return
        }

        do {
            try PasswordAuth.shared.setPassword(password)
            currentStep = .selectApps
        } catch {
            passwordError = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool?
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(icon == "hand.raised.fill" ? .orange : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let granted = isGranted {
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if let action = action {
                    Button("Grant", action: action)
                        .controlSize(.small)
                }
            } else {
                Text("Auto")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.15))
        )
    }
}
