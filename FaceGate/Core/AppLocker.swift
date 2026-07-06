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

    /// One-shot work item to check for windows after a delay when an app is launching.
    private var windowDetectionWorkItem: DispatchWorkItem?

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

        // Step 1: Immediately hide the locked app if in Full Screen mode.
        let overlayMode = UserDefaults.standard.integer(forKey: FGConstants.authOverlayModeKey)
        if overlayMode == 0 {
            runningApp.hide()
        } else {
            runningApp.activate(options: [.activateIgnoringOtherApps])
        }

        // Start Face ID authentication if available.
        if AuthenticationManager.shared.isFaceUnlockAvailable {
            AuthenticationManager.shared.authenticateWithFace { [weak self] success in
                if success {
                    self?.unlockCurrentApp()
                }
            }
        }

        // Step 2: Present auth overlays.
        showOverlays(for: bundleIdentifier)
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

        // Stop face authentication.
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
    }

    /// Called when authentication fails and user chooses to cancel.
    /// Terminates the locked app instead of revealing it.
    func terminateBlockedApp() {
        dismissOverlays()
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
        appMonitor.didUnblockApp()
    }

    /// Dismiss all overlays without unlocking (e.g., if FaceGate is quitting).
    func dismissOverlays() {
        windowDetectionWorkItem?.cancel()
        windowDetectionWorkItem = nil
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
                // If no window found (e.g. launching), show a temporary full screen shield on main screen and poll.
                showTemporaryFullScreenOverlay(appName: appName, bundleIdentifier: bundleIdentifier)
            }
        } else {
            // Present auth overlays on all screens.
            for (index, screen) in screens.enumerated() {
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
                if screen == activeScreen {
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeMain()
                } else {
                    panel.orderFront(nil)
                }
                overlayPanels[CGWindowID(1000 + index)] = panel
            }
        }

        // Activate FaceGate so it becomes the active app and can receive keyboard input.
        NSApp.activate(ignoringOtherApps: true)

        // Hiding a running app causes macOS to asynchronously focus the next app.
        // We activate again on the next runloop tick to override this focus shift.
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
        let overlayMode = UserDefaults.standard.integer(forKey: FGConstants.authOverlayModeKey)
        if overlayMode == 0 {
            blockedRunningApp?.hide()
        }
        dismissOverlays()
        AuthenticationManager.shared.stopFaceAuth()
        onUnlockAction = nil
        currentlyBlockedApp = nil
        blockedRunningApp = nil
        appMonitor.didUnblockApp()
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
            // If window configuration changed, recreate the overlays
            showOverlays(for: bundleIdentifier)
        }
    }

    /// Show a temporary full screen shield on the active screen and wait for the blocked
    /// app's windows to become available, then transition to window-specific overlays.
    private func showTemporaryFullScreenOverlay(appName: String, bundleIdentifier: String) {
        let screens = NSScreen.screens
        let mouseLocation = NSEvent.mouseLocation
        guard let activeScreen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? screens.first else { return }
        guard let pid = blockedRunningApp?.processIdentifier else { return }

        let panel = AuthOverlayPanel(
            screen: activeScreen,
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

        // Remove any prior observer before registering a new one.
        if let existing = windowActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(existing)
            windowActivationObserver = nil
        }

        // Register for the blocked app's activation to detect window creation.
        let center = NSWorkspace.shared.notificationCenter
        windowActivationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            self.checkAndTransitionFromTemporaryOverlay(bundleIdentifier: bundleIdentifier)
        }

        // One-shot delayed check as fallback if the activation notification was missed.
        let workItem = DispatchWorkItem { [weak self] in
            self?.checkAndTransitionFromTemporaryOverlay(bundleIdentifier: bundleIdentifier)
        }
        windowDetectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    /// Check if the blocked app's windows are now available and transition from
    /// the temporary full-screen shield to window-specific overlays.
    private func checkAndTransitionFromTemporaryOverlay(bundleIdentifier: String) {
        guard let app = blockedRunningApp else { return }
        let windows = getAppWindowFrames(for: app.processIdentifier)
        if !windows.isEmpty {
            windowDetectionWorkItem?.cancel()
            windowDetectionWorkItem = nil
            showOverlays(for: bundleIdentifier)
        }
    }
}
