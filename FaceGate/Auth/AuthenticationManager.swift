import Combine
import Foundation

/// Unified authentication manager that orchestrates all auth methods.
/// Follows the priority hierarchy: Face Unlock → Touch ID → App Password.
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()

    /// Current authentication state.
    @Published var authState: AuthState = .idle

    /// Number of failed attempts in the current session.
    @Published var failedAttempts: Int = 0

    /// Whether the user is locked out due to too many failures.
    @Published var isLockedOut: Bool = false

    private var lockoutTimer: Timer?

    private let passwordAuth = PasswordAuth.shared
    private let touchIDAuth = TouchIDAuth.shared
    let faceAuthManager = FaceAuthManager()

    /// Continuation to execute after authentication resolves (e.g. opening Settings).
    /// Used instead of creating a second LAContext, which triggers a dual-auth/stuck-overlay bug.
    var pendingContinuation: (() -> Void)?

    private init() {}

    enum AuthOwner: Equatable {
        case appLock(String)
        case action(String)
    }

    // MARK: - Auth State

    enum AuthState: Equatable {
        case idle
        case authenticating(AuthMethod)
        case success
        case failed(String)
        case lockedOut(TimeInterval)
    }

    // MARK: - Public API

    /// Whether face unlock is available and enrolled.
    var isFaceUnlockAvailable: Bool {
        faceAuthManager.isAvailable
    }

    /// Get the list of available auth methods for the current session.
    func availableAuthMethods() -> [AuthMethod] {
        var methods: [AuthMethod] = []

        if faceAuthManager.isAvailable {
            methods.append(.faceUnlock)
        }

        if touchIDAuth.canUse {
            methods.append(.touchID)
        }

        if passwordAuth.isPasswordSet {
            methods.append(.appPassword)
        }

        return methods
    }

    /// Authenticate using Face Unlock.
    /// - Parameter completion: Called with the result.
    func authenticateWithFace(owner: AuthOwner, completion: @escaping (Bool) -> Void) {
        guard !isLockedOut else {
            completion(false)
            return
        }

        guard !faceAuthInProgress else {
            completion(false)
            return
        }

        stopTouchIDAuth() // Ensure pending Touch ID is cancelled before starting face auth

        let sessionID = UUID()
        currentSessionID = sessionID
        currentAuthOwner = owner
        faceAuthInProgress = true

        authState = .authenticating(.faceUnlock)

        faceAuthManager.startAuthentication { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.currentSessionID == sessionID,
                      self.currentAuthOwner == owner,
                      self.faceAuthInProgress else { return }
                self.faceAuthInProgress = false
                self.currentSessionID = nil
                self.currentAuthOwner = nil
                if success {
                    self.onAuthSuccess()
                    completion(true)
                } else {
                    // Don't count face auth timeout as a failure — let user try fallbacks.
                    self.authState = .idle
                    completion(false)
                }
            }
        }
    }

    /// Stop any in-progress face authentication.
    func stopFaceAuth(owner: AuthOwner? = nil) {
        guard owner == nil || currentAuthOwner == owner else { return }
        faceAuthManager.stopAuthentication()
        faceAuthInProgress = false
        if case .authenticating(let method) = authState, method == .faceUnlock {
            authState = .idle
        }
        if owner == nil || currentAuthOwner == owner {
            if !touchIDInProgress {
                currentSessionID = nil
                currentAuthOwner = nil
            }
        }
    }

    /// Prevents duplicate Touch ID prompts when multiple overlay panels fire
    /// onAppear simultaneously (e.g. multi-monitor setups).
    private var touchIDInProgress = false
    private var faceAuthInProgress = false
    private var currentSessionID: UUID?
    private var currentAuthOwner: AuthOwner?

    /// Whether a Touch ID evaluation is currently in progress.
    /// Used by AppMonitor to suppress switch-away handling during the system
    /// Touch ID dialog (which causes a transient app-activation for SecurityAgent).
    var isTouchIDInProgress: Bool { touchIDInProgress }

    /// Authenticate using Touch ID.
    /// - Parameter appName: Name of the app being unlocked (shown in Touch ID dialog).
    /// - Parameter completion: Called with the result.
    func authenticateWithTouchID(appName: String, owner: AuthOwner, completion: @escaping (Bool) -> Void) {
        guard !isLockedOut else {
            completion(false)
            return
        }

        guard !touchIDInProgress else {
            completion(false)
            return
        }

        let sessionID = UUID()
        currentSessionID = sessionID
        currentAuthOwner = owner
        touchIDInProgress = true
        authState = .authenticating(.touchID)

        touchIDAuth.authenticate(reason: "Unlock \(appName)") { [weak self] result in
            guard let self = self else { return }
            guard self.currentSessionID == sessionID,
                  self.currentAuthOwner == owner,
                  self.touchIDInProgress else { return }
            self.touchIDInProgress = false
            self.currentSessionID = nil
            self.currentAuthOwner = nil
            AppLocker.shared.restoreTouchIDMode()
            // Ignore stale callbacks from cancelled/invalidated LAContext that arrive
            // after another auth method (e.g. password) already changed the state.
            guard case .authenticating(.touchID) = self.authState else { return }
            switch result {
            case .success:
                self.onAuthSuccess()
                completion(true)
            case .failure(let error):
                switch error {
                case .cancelled, .fallbackRequested:
                    self.authState = .idle
                default:
                    self.onAuthFailure(error.localizedDescription)
                }
                completion(false)
            }
        }
    }

    /// Stop any in-progress Touch ID authentication.
    func stopTouchIDAuth(owner: AuthOwner? = nil) {
        guard owner == nil || currentAuthOwner == owner else { return }
        touchIDAuth.cancelAuthentication()
        touchIDInProgress = false
        AppLocker.shared.restoreTouchIDMode()
        if case .authenticating(let method) = authState, method == .touchID {
            authState = .idle
        }
        if owner == nil || currentAuthOwner == owner {
            currentSessionID = nil
            currentAuthOwner = nil
        }
    }

    /// Cancel all in-progress authentication and clear pending state.
    /// Called when the user switches to a different protected app.
    func cancelCurrentAuthentication() {
        stopTouchIDAuth()
        stopFaceAuth()
        pendingContinuation = nil
        authState = .idle
    }

    /// Called after authentication completes (success, cancel, or switch-away)
    /// to clear the pending continuation.
    func finishAuthentication() {
        pendingContinuation = nil
    }

    /// Authenticate using the app password.
    /// - Parameter password: The password the user entered.
    /// - Returns: `true` if authentication succeeded.
    func authenticateWithPassword(_ password: String, owner: AuthOwner? = nil) -> Bool {
        guard !isLockedOut else { return false }

        stopTouchIDAuth() // Ensure Touch ID is cancelled if active
        stopFaceAuth(owner: owner)

        authState = .authenticating(.appPassword)

        if passwordAuth.verifyPassword(password) {
            onAuthSuccess()
            return true
        } else {
            onAuthFailure("Incorrect password")
            return false
        }
    }

    /// Reset the failed attempts counter (e.g., after successful auth).
    func resetAttempts() {
        failedAttempts = 0
        isLockedOut = false
        lockoutTimer?.invalidate()
        lockoutTimer = nil
        authState = .idle
        stopTouchIDAuth()
        stopFaceAuth()
    }

    // MARK: - Private

    private func onAuthSuccess() {
        authState = .success
        failedAttempts = 0
        isLockedOut = false
        lockoutTimer?.invalidate()
        stopFaceAuth()
    }

    private func onAuthFailure(_ message: String) {
        failedAttempts += 1

        if failedAttempts >= FGConstants.maxFailedAttempts {
            isLockedOut = true
            authState = .lockedOut(FGConstants.lockoutDuration)

            // Auto-unlock after lockout duration.
            lockoutTimer = Timer.scheduledTimer(withTimeInterval: FGConstants.lockoutDuration, repeats: false) { [weak self] _ in
                self?.isLockedOut = false
                self?.failedAttempts = 0
                self?.authState = .idle
            }
        } else {
            authState = .failed(message)
        }
    }
}
