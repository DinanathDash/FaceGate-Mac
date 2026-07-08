import AppKit
import SwiftUI

/// Manages the "shield" — hiding locked apps and presenting auth overlays.
/// Coordinates between AppMonitor (detection) and AuthenticationManager (auth).
final class AppLocker: ObservableObject {
    static let shared = AppLocker()

    /// The bundle ID of the app currently being blocked (if any).
    @Published private(set) var currentlyBlockedApp: String?

    /// The running application instance being blocked.
    private(set) var blockedRunningApp: NSRunningApplication?

    /// Optional action to execute after unlocking (e.g. opening Settings)
    var onUnlockAction: (() -> Void)?

    /// Active overlay panels mapped by window IDs (or dummy IDs for fullscreen).
    private var overlayPanels: [CGWindowID: AuthOverlayPanel] = [:]


    /// Timer used to periodically realign overlays if the locked app's windows move/resize.
    private var windowAlignmentTimer: Timer?

    /// Observer for when the blocked app activates — triggers immediate overlay alignment.
    private var windowActivationObserver: NSObjectProtocol?

    private let sessionManager = SessionManager.shared
    private let appMonitor = AppMonitor.shared

    private init() {}

    // MARK: - Public API

    /// Block a locked app: hide it and show the auth overlay.
    /// - Parameters:
    ///   - bundleIdentifier: The locked app's bundle ID.
    ///   - runningApp: The NSRunningApplication instance to hide.
    func blockApp(bundleIdentifier: String, runningApp: NSRunningApplication) {
        // Avoid re-blocking if we're already blocking this app.
        if currentlyBlockedApp == bundleIdentifier { return }

        currentlyBlockedApp = bundleIdentifier
        blockedRunningApp = runningApp
        appMonitor.didBlockApp(bundleIdentifier)

        // Step 1: Present auth overlays FIRST so the locked app's content is never
        // visible to the user. This prevents the privacy flash described in Bug 4.
        showOverlays(for: bundleIdentifier)

        // Step 2: Bring the locked app forward so macOS stays on its space.
        // Use orderFront-style activation — don't make it key or steal focus,
        // as the system Touch ID dialog needs uncontested focus (MakLock pattern).
        runningApp.activate(options: [])
    }

    /// Called when authentication succeeds — reveal the app and dismiss overlays.
    func unlockCurrentApp() {
        guard let bundleId = currentlyBlockedApp else { return }

        // Save references before clearing state.
        let app = blockedRunningApp

        // Clear state BEFORE activate to prevent re-block during activation notification.
        currentlyBlockedApp = nil
        blockedRunningApp = nil
        appMonitor.didUnblockApp()

        let action = onUnlockAction
        onUnlockAction = nil

        let continuation = AuthenticationManager.shared.pendingContinuation
        AuthenticationManager.shared.finishAuthentication()

        // Stop any in-progress biometric authentication.
        AuthenticationManager.shared.stopTouchIDAuth()
        AuthenticationManager.shared.stopFaceAuth()

        // Create an unlock session (no-op for "lock immediately" — duration is 0).
        sessionManager.createSession(for: bundleId)
        appMonitor.recordUnlock(for: bundleId)

        // Dismiss overlays.
        dismissOverlays()

        // Unhide and activate the app.
        if let app = app {
            app.unhide()
            app.activate(options: [.activateIgnoringOtherApps])
        }

        action?()
        continuation?()
    }

    /// Called when authentication fails and user chooses to cancel.
    /// Terminates the locked app instead of revealing it.
    func terminateBlockedApp() {
        dismissOverlays()
        AuthenticationManager.shared.stopTouchIDAuth()
        AuthenticationManager.shared.stopFaceAuth()

        if let app = blockedRunningApp {
            app.terminate()

            // Force terminate after a brief delay if the app doesn't comply.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }

        currentlyBlockedApp = nil
        blockedRunningApp = nil
        onUnlockAction = nil
        AuthenticationManager.shared.finishAuthentication()
        appMonitor.didUnblockApp()
    }

    /// Dismiss all overlays without unlocking (e.g., if FaceGate is quitting).
    func dismissOverlays() {
        windowAlignmentTimer?.invalidate()
        windowAlignmentTimer = nil
        if let observer = windowActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            windowActivationObserver = nil
        }
        for panel in overlayPanels.values {
            panel.orderOut(nil)
        }
        overlayPanels.removeAll()
    }

    /// Temporarily adjust the window level of the overlay (e.g. to show system prompts).
    func setOverlayWindowLevel(_ level: NSWindow.Level) {
        for panel in overlayPanels.values {
            panel.level = level
        }
    }

    /// Restore the overlay panels to their default window level based on the active shield mode.
    func restoreOverlayWindowLevel() {
        let overlayMode = UserDefaults.standard.integer(forKey: FGConstants.authOverlayModeKey)
        let defaultLevel: NSWindow.Level = (overlayMode == 1) ? .floating : .screenSaver
        setOverlayWindowLevel(defaultLevel)
    }

    /// Configure overlays for Touch ID: lower window level and enable mouse event
    /// passthrough so the system Touch ID dialog can receive focus and events.
    /// Mirrors the pattern used by MakLock's OverlayWindowService.setTouchIDMode(_:).
    func setTouchIDMode() {
        for panel in overlayPanels.values {
            panel.level = .statusBar
            panel.ignoresMouseEvents = true
        }
        if let actionWindow = ActionAuthWindow.sharedActiveWindow {
            actionWindow.level = .statusBar
            actionWindow.ignoresMouseEvents = true
        }
    }

    /// Restore overlays after Touch ID completes (reverses setTouchIDMode).
    func restoreTouchIDMode() {
        let overlayMode = UserDefaults.standard.integer(forKey: FGConstants.authOverlayModeKey)
        let defaultLevel: NSWindow.Level = (overlayMode == 1) ? .floating : .screenSaver
        for panel in overlayPanels.values {
            panel.level = defaultLevel
            panel.ignoresMouseEvents = false
        }
        if let actionWindow = ActionAuthWindow.sharedActiveWindow {
            actionWindow.level = .floating
            actionWindow.ignoresMouseEvents = false
        }
    }

    // MARK: - Private

    /// Create and show auth overlay panels.
    private func showOverlays(for bundleIdentifier: String) {
        dismissOverlays()

        let appName = LockedAppsManager.shared.displayName(for: bundleIdentifier) ?? "Application"
        let overlayMode = UserDefaults.standard.integer(forKey: FGConstants.authOverlayModeKey)
        
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? screens.first

        if overlayMode == 1, let app = blockedRunningApp {
            let windows = getAppWindowFrames(for: app.processIdentifier)
            if !windows.isEmpty {
                for (windowID, frame) in windows {
                    let adjustedFrame = calculateOverlayFrame(from: convertQuartzToAppKit(rect: frame))
                    let panel = AuthOverlayPanel(
                        frame: adjustedFrame,
                        appName: appName,
                        bundleIdentifier: bundleIdentifier,
                        onAuthenticated: { [weak self] in
                            self?.unlockCurrentApp()
                        },
                        onCancel: { [weak self] in
                            self?.terminateBlockedApp()
                        }
                    )
                    panel.orderFront(nil)
                    overlayPanels[windowID] = panel
                }
                
                if let first = overlayPanels.values.first {
                    first.makeKeyAndOrderFront(nil)
                }
                
                // Track window updates periodically
                startWindowAlignmentTimer(for: app.processIdentifier, appName: appName, bundleIdentifier: bundleIdentifier)
            } else {
                // No windows yet (app is cold-launching). Show a full-screen overlay as the
                // secure initial state, and let the windowAlignmentTimer handle the transition
                // to window-specific overlays once the app's windows materialize.
                if let screen = activeScreen {
                    let panel = AuthOverlayPanel(
                        screen: screen,
                        appName: appName,
                        bundleIdentifier: bundleIdentifier,
                        onAuthenticated: { [weak self] in
                            self?.unlockCurrentApp()
                        },
                        onCancel: { [weak self] in
                            self?.terminateBlockedApp()
                        }
                    )
                    panel.makeKeyAndOrderFront(nil)
                    overlayPanels[0] = panel
                }

                // Start the alignment timer — when windows appear, alignOverlayWindows will
                // detect the ID mismatch ({0} vs real IDs) and call showOverlays to transition.
                startWindowAlignmentTimer(for: app.processIdentifier, appName: appName, bundleIdentifier: bundleIdentifier)
            }
        } else {
            var targetScreens: [(index: Int, screen: NSScreen)] = []

            if let app = blockedRunningApp {
                let appWindows = getAppWindowFrames(for: app.processIdentifier)
                if !appWindows.isEmpty {
                    var seenIndices = Set<Int>()
                    for (index, screen) in screens.enumerated() {
                        for (_, windowFrame) in appWindows {
                            let appKitFrame = convertQuartzToAppKit(rect: windowFrame)
                            if screen.frame.intersects(appKitFrame) {
                                if seenIndices.insert(index).inserted {
                                    targetScreens.append((index: index, screen: screen))
                                }
                                break
                            }
                        }
                    }
                }
            }

            if targetScreens.isEmpty {
                if let screen = activeScreen {
                    let index = screens.firstIndex(of: screen) ?? 0
                    targetScreens.append((index: index, screen: screen))
                } else if let screen = screens.first {
                    targetScreens.append((index: 0, screen: screen))
                }
            }

            for (index, screen) in targetScreens {
                let isScreenPrimary = (targetScreens.count == 1) || (screen == activeScreen)
                let panel = AuthOverlayPanel(
                    screen: screen,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    isPrimary: isScreenPrimary,
                    onAuthenticated: { [weak self] in
                        self?.unlockCurrentApp()
                    },
                    onCancel: { [weak self] in
                        self?.terminateBlockedApp()
                    }
                )
                if isScreenPrimary {
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeMain()
                } else {
                    panel.orderFront(nil)
                }
                overlayPanels[CGWindowID(1000 + index)] = panel
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        // runningApp.activate(options: []) later in blockApp can steal key status
        // from the overlay. We re-assert on the next runloop tick to guarantee
        // the overlay remains key for Touch ID.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let activeScreen = activeScreen {
                self.overlayPanels.first(where: { $0.value.screen == activeScreen })?.value.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Called when the user switches focus to another app.
    /// Gracefully hides the blocked application and dismisses overlays.
    func handleSwitchAway() {
        // Don't hide the app — interferes with Touch ID focus.
        dismissOverlays()
        AuthenticationManager.shared.stopTouchIDAuth()
        AuthenticationManager.shared.stopFaceAuth()
        onUnlockAction = nil
        AuthenticationManager.shared.finishAuthentication()
        currentlyBlockedApp = nil
        blockedRunningApp = nil
        appMonitor.didUnblockApp()
    }

    /// Stop active biometrics while preserving the blocked app and overlay state.
    /// Used by App Window mode when the protected app is no longer frontmost.
    func suspendCurrentLockAuthentication() {
        guard let bundleId = currentlyBlockedApp else { return }
        windowAlignmentTimer?.invalidate()
        windowAlignmentTimer = nil
        AuthenticationManager.shared.stopTouchIDAuth(owner: .appLock(bundleId))
        AuthenticationManager.shared.stopFaceAuth(owner: .appLock(bundleId))
    }

    /// Bring existing overlay panels back to the front of the window stack.
    /// Called when the user Cmd+Tabs or clicks back to a locked app in App Window mode.
    func bringOverlaysToFront() {
        guard !overlayPanels.isEmpty else { return }
        for panel in overlayPanels.values {
            panel.orderFront(nil)
        }
        if let first = overlayPanels.values.first {
            first.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        if let app = blockedRunningApp, let bundleId = currentlyBlockedApp {
            let appName = LockedAppsManager.shared.displayName(for: bundleId) ?? "Application"
            startWindowAlignmentTimer(for: app.processIdentifier, appName: appName, bundleIdentifier: bundleId)
        }

        if case .authenticating = AuthenticationManager.shared.authState {
            return
        }
        NotificationCenter.default.post(name: .authOverlayDidBecomeActive, object: currentlyBlockedApp)
    }

    // MARK: - App Window Mode Helpers

    /// Retrieve all onscreen window frames and IDs for a given process PID.
    private func getAppWindowFrames(for pid: pid_t) -> [(CGWindowID, CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var windows: [(CGWindowID, CGRect)] = []
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }
            
            // Layer 0 is standard application windows.
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }
            
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID else { continue }
            
            if let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                // Ignore small accessory/dock/shadow/helper elements.
                if rect.width > 120 && rect.height > 120 {
                    windows.append((windowID, rect))
                }
            }
        }
        return windows
    }

    /// Convert Quartz (top-left origin) coordinates to AppKit (bottom-left origin) coordinates.
    private func convertQuartzToAppKit(rect: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return rect }
        let globalFrame = screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard !globalFrame.isNull else { return rect }
        
        let primaryScreenHeight = primaryScreen.frame.height
        let quartzYTop = primaryScreenHeight - globalFrame.maxY
        let appKitYTop = globalFrame.maxY - (rect.origin.y - quartzYTop)
        let appKitY = appKitYTop - rect.size.height
        return CGRect(x: rect.origin.x, y: appKitY, width: rect.size.width, height: rect.size.height)
    }

    /// Enforce a minimum size of 400x500 for the overlay to avoid clipping UI components.
    private func calculateOverlayFrame(from windowFrame: CGRect) -> CGRect {
        let minWidth: CGFloat = 400
        let minHeight: CGFloat = 500
        
        var targetFrame = windowFrame
        
        if targetFrame.width < minWidth {
            let delta = minWidth - targetFrame.width
            targetFrame.origin.x -= delta / 2
            targetFrame.size.width = minWidth
        }
        
        if targetFrame.height < minHeight {
            let delta = minHeight - targetFrame.height
            targetFrame.origin.y -= delta / 2
            targetFrame.size.height = minHeight
        }
        
        return targetFrame
    }

    /// Dynamically adjust the overlays if the locked app's windows move/resize/open/close.
    /// Uses a slower background timer as fallback and NSWorkspace activation notifications
    /// for event-triggered re-alignment.
    private func startWindowAlignmentTimer(for pid: pid_t, appName: String, bundleIdentifier: String) {
        // Remove any prior observer before registering a new one.
        if let existing = windowActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
            windowActivationObserver = nil
        }

        // Register for activation notifications so we realign immediately when the user
        // switches back to the locked app, rather than waiting for the next timer tick.
        let center = NSWorkspace.shared.notificationCenter
        windowActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            self.alignOverlayWindows(pid: pid, bundleIdentifier: bundleIdentifier)
        }

        // Fallback timer at a reduced cadence to catch moves that happen without an activation.
        windowAlignmentTimer?.invalidate()
        windowAlignmentTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.alignOverlayWindows(pid: pid, bundleIdentifier: bundleIdentifier)
        }
    }

    /// Check the locked app's current window configuration and update overlay panels accordingly.
    private func alignOverlayWindows(pid: pid_t, bundleIdentifier: String) {
        let windows = getAppWindowFrames(for: pid)
        guard !windows.isEmpty else { return }

        let existingIDs = Set(overlayPanels.keys)
        let newIDs = Set(windows.map { $0.0 })

        if existingIDs == newIDs {
            for (windowID, frame) in windows {
                if let panel = overlayPanels[windowID] {
                    let adjustedFrame = calculateOverlayFrame(from: convertQuartzToAppKit(rect: frame))
                    if panel.frame != adjustedFrame {
                        panel.setFrame(adjustedFrame, display: true, animate: false)
                    }
                }
            }
        } else {
            let removedIDs = existingIDs.subtracting(newIDs)

            if case .authenticating = AuthenticationManager.shared.authState {
                guard removedIDs.isEmpty else {
                    return
                }
            }

            if !removedIDs.isEmpty {
                showOverlays(for: bundleIdentifier)
                return
            }

            let added = windows.filter { !existingIDs.contains($0.0) }
            let appName = LockedAppsManager.shared.displayName(for: bundleIdentifier) ?? "Application"
            for (windowID, frame) in added {
                let adjustedFrame = calculateOverlayFrame(from: convertQuartzToAppKit(rect: frame))
                let panel = AuthOverlayPanel(
                    frame: adjustedFrame,
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    onAuthenticated: { [weak self] in
                        self?.unlockCurrentApp()
                    },
                    onCancel: { [weak self] in
                        self?.terminateBlockedApp()
                    }
                )
                panel.orderFront(nil)
                overlayPanels[windowID] = panel
            }
        }
    }

}
