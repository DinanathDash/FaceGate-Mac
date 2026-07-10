import AVFoundation
import SwiftUI

/// Face enrollment UI view with camera preview, face guide, and progress tracking.
/// Used during initial setup and when re-enrolling from settings.
struct FaceEnrollmentView: View {
    @StateObject private var enrollmentManager = FaceEnrollmentManager()

    /// Called when enrollment completes (success or skip).
    var onComplete: () -> Void
    var onBack: (() -> Void)? = nil
    var isInSettings: Bool = false

    /// Whether this is adding a new face to an existing enrollment
    var isAddingFace: Bool = false
    
    static var hasEnrolledInThisSession = false

    @State private var cameraAuthorization: AVAuthorizationStatus = .notDetermined

    private var staticStatusMessage: String {
        switch enrollmentManager.state {
        case .idle:
            return "Position your face in the frame"
        case .capturing:
            return "Follow the prompts on the camera screen"
        case .processing:
            return "Processing face data"
        case .success:
            return "Face enrolled successfully!"
        case .failed(let message):
            return "Enrollment failed: \(message)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header.
            VStack(spacing: 4) {
                Image(systemName: "faceid")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hue: 0.58, saturation: 0.7, brightness: 0.95),
                                     Color(hue: 0.61, saturation: 0.75, brightness: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Face Enrollment")
                    .font(.title.bold())

                Text(staticStatusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                if !isAddingFace && !isInSettings {
                    Text("You can add up to 3 faces from Settings")
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 0)

            // Warning message (above the video screen)
            VStack(spacing: 2) {
                Text(enrollmentManager.warningMessage)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(height: 20)
            .animation(.easeInOut(duration: 0.25), value: enrollmentManager.warningMessage)
            .padding(.bottom, 6)

            // Camera preview or permission-denied state.
            ZStack {
                if cameraAuthorization == .denied || cameraAuthorization == .restricted {
                    cameraDeniedView
                } else if enrollmentManager.state == .capturing || enrollmentManager.state == .idle {
                    CameraPreviewView(captureSession: enrollmentManager.camera.captureSession)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    FaceGuideOverlay(
                        faceDetected: enrollmentManager.capturedCount > 0,
                        quality: enrollmentManager.currentQuality
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if enrollmentManager.state == .capturing {
                        directionIndicator(for: enrollmentManager.currentStep)
                    }

                } else if enrollmentManager.state == .processing {
                    processingView
                } else if enrollmentManager.state == .success {
                    successView
                } else if case .failed(let message) = enrollmentManager.state {
                    failedView(message: message)
                }
            }
            .frame(width: 320, height: 240)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )

            // Progress bar placeholder to prevent UI jumps.
            VStack(spacing: 6) {
                if enrollmentManager.state == .capturing {
                    ProgressView(
                        value: Double(enrollmentManager.capturedCount),
                        total: Double(enrollmentManager.targetFrameCount)
                    )
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                    Text("\(enrollmentManager.capturedCount) of \(enrollmentManager.targetFrameCount) captures")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 320, height: 40)
            .padding(.top, 8)

            if !isInSettings {
                Spacer()
            } else {
                Spacer().frame(height: 24)
            }

            // Action buttons.
            actionButtons
        }
        .padding(.top, isInSettings ? 32 : 0)
        .padding(.bottom, isInSettings ? 32 : 0)
        .frame(width: isInSettings ? 460 : nil)
        .frame(
            maxWidth: isInSettings ? nil : .infinity,
            maxHeight: isInSettings ? nil : .infinity
        )
        .onAppear {
            enrollmentManager.isAddingFace = isAddingFace
            if FaceEnrollmentView.hasEnrolledInThisSession && !isInSettings {
                enrollmentManager.state = .success
            } else {
                checkCameraAndStart()
            }
        }
        .onDisappear {
            // Always cancel enrollment when disappearing
            enrollmentManager.cancelEnrollment()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SetupWindowWillClose"))) { _ in
            // Handle the case where the user closes the setup window via the red traffic light button.
            // AppKit window closing sometimes prevents SwiftUI onDisappear from firing immediately.
            enrollmentManager.cancelEnrollment()
            FaceEnrollmentView.hasEnrolledInThisSession = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard enrollmentManager.state == .idle else { return }
            checkCameraAndStart()
        }
        .onChange(of: enrollmentManager.state) { newState in
            if newState == .success {
                FaceEnrollmentView.hasEnrolledInThisSession = true
            }
        }
    }

    // MARK: - Camera Permission

    private func checkCameraAndStart() {
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraAuthorization {
        case .authorized:
            enrollmentManager.camera.permissionGranted = true
            enrollmentManager.camera.error = nil
            enrollmentManager.startEnrollment()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak enrollmentManager] granted in
                DispatchQueue.main.async {
                    if granted {
                        guard let manager = enrollmentManager else { return }
                        manager.camera.permissionGranted = true
                        manager.startEnrollment()
                    } else {
                        cameraAuthorization = .denied
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Camera Denied View

    private var cameraDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 36))
                .foregroundColor(.red.opacity(0.8))

            Text("Camera Access Denied")
                .font(.headline)
                .foregroundColor(.white)

            Text("FaceGate needs camera access to enroll your face. Please enable it in System Settings.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Open System Settings") {
                CameraManager.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - State Views

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Face Captured!")
                .font(.headline)
                .foregroundColor(.white)
            Text("Please allow Keychain access to securely store your data.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("Face Enrolled!")
                .font(.headline)
                .foregroundColor(.white)
            if enrollmentManager.capturedCount > 0 {
                Text("\(enrollmentManager.capturedCount) reference captures saved")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Enrollment Failed")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if cameraAuthorization == .denied || cameraAuthorization == .restricted {
            VStack(spacing: 16) {
                secondaryButton(isInSettings ? "Cancel" : "Skip") { onComplete() }
                if let onBack = onBack { backButton(action: onBack) }
            }
        } else {
            switch enrollmentManager.state {
            case .idle:
                VStack(spacing: 16) {
                    secondaryButton(isInSettings ? "Cancel" : "Skip for Now") { onComplete() }
                    if let onBack = onBack { backButton(action: onBack) }
                }

            case .capturing:
                VStack(spacing: 8) {
                    secondaryButton(isInSettings ? "Cancel" : "Skip for Now") {
                        enrollmentManager.cancelEnrollment()
                        onComplete()
                    }
                    HStack(spacing: 12) {
                        if let onBack = onBack { backButton(action: onBack) }
                        primaryButton("Recapture") { enrollmentManager.startEnrollment() }
                    }
                }

            case .processing:
                EmptyView()

            case .success:
                VStack(spacing: 16) {
                    secondaryButton("Re-enroll") { enrollmentManager.startEnrollment() }
                    HStack(spacing: 12) {
                        if let onBack = onBack { backButton(action: onBack) }
                        primaryButton("Continue") { onComplete() }
                    }
                }

            case .failed:
                VStack(spacing: 16) {
                    secondaryButton(isInSettings ? "Cancel" : "Skip") { onComplete() }
                    HStack(spacing: 12) {
                        if let onBack = onBack { backButton(action: onBack) }
                        primaryButton("Try Again") { enrollmentManager.startEnrollment() }
                    }
                }
            }
        }
    }

    // MARK: - Button Styles
    
    private func backButton(action: @escaping () -> Void) -> some View {
        Button("Back", action: action)
            .controlSize(.large)
            .frame(minWidth: 120)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(minWidth: 120)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func directionIndicator(for step: FaceEnrollmentManager.EnrollmentStep) -> some View {
        if step != .straight {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AnimatedDirectionIndicator(
                        icon: indicatorIcon(for: step),
                        direction: step == .left ? .left : .right
                    )
                    .padding(8)
                }
            }
        }
    }

    private func indicatorIcon(for step: FaceEnrollmentManager.EnrollmentStep) -> String {
        switch step {
        case .straight: return ""
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        }
    }
}
