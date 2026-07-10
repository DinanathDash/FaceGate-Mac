import AppKit
import SwiftUI
import Sparkle

/// AppDelegate for AppKit bridging — handles lifecycle events that SwiftUI can't.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    private var setupWindow: NSWindow?
    private(set) var updaterController: SPUStandardUpdaterController?
    
    // MARK: - Menu Bar App State
    private var statusItem: NSStatusItem?
    private var menuBuilder: MenuBuilder?
    private var classicPopover: NSPopover?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Sparkle updater for automatic updates.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Pre-load the Core ML face embedding model to avoid cold-start delay.
        // The ANE compilation happens at load time (~200-500ms) — pay this cost now.
        FaceEmbedder.shared.loadModel()

        // Start the schedule manager so it begins evaluating lock/unlock time windows.
        _ = AppScheduleManager.shared

        // Wire up AppMonitor ↔ AppLocker.
        AppMonitor.shared.onLockedAppDetected = { [weak self] bundleId, runningApp in
            _ = self  // silence warning
            AppLocker.shared.blockApp(bundleIdentifier: bundleId, runningApp: runningApp)
        }

        // Initialize as accessory so we don't show in the Dock.
        NSApp.setActivationPolicy(.accessory)
        
        // Set up the custom menu bar item and popover panel
        setupMenuBarItem()

        // Start monitoring if setup is complete, otherwise open setup after a delay.
        if UserDefaults.standard.bool(forKey: FGConstants.setupCompletedKey) {
            AppMonitor.shared.startMonitoring()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSetupWindow()
            }
        }

        // Sync uninstall protection state on startup.
        syncUninstallProtection()

        // Register secret kill hotkey.
        GlobalHotkeyManager.shared.registerShortcut()

        // Listen for "open settings" notifications from MenuBarView.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: Notification.Name.openSettings,
            object: nil
        )

        // Listen for "open setup" notifications from MenuBarView.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSetupWindow),
            name: Notification.Name.openSetup,
            object: nil
        )

        // Lock all apps when the Mac sleeps or locks (if enabled).
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsNC.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        // Intercept the default SwiftUI Settings shortcut (Cmd+,)
        // so it opens our custom SettingsWindow instead of the default blank SwiftUI Settings scene.
        DispatchQueue.main.async {
            if let menu = NSApp.mainMenu {
                for item in menu.items {
                    if let submenu = item.submenu {
                        for subitem in submenu.items {
                            if subitem.keyEquivalent == "," {
                                subitem.target = self
                                subitem.action = #selector(self.openSettingsWindow)
                            }
                        }
                    }
                }
            }
        }
    }

    var isAuthorizedToQuit = false

    var isSettingsWindowVisible: Bool {
        NSApp.windows.contains { $0.title == "Settings" && $0.isVisible }
    }



    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If settings window is open or we've pre-authorized, allow quitting without authentication.
        if isAuthorizedToQuit || isSettingsWindowVisible {
            cleanup()
            return .terminateNow
        }

        let setupDone = UserDefaults.standard.bool(forKey: FGConstants.setupCompletedKey)
        let hasLockedApps = !LockedAppsManager.shared.lockedApps.isEmpty

        if setupDone && hasLockedApps {
            // Show auth dialog alert fallback for system-level quit signals.
            let alert = NSAlert()
            alert.messageText = "Authenticate to Quit"
            alert.informativeText = "FaceGate is protecting your apps. Enter your password to quit."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Quit Anyway")
            alert.alertStyle = .warning

            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                cleanup()
                return .terminateNow
            } else {
                return .terminateCancel
            }
        }

        cleanup()
        return .terminateNow
    }

    private func cleanup() {
        AppLocker.shared.dismissOverlays()
        AppMonitor.shared.stopMonitoring()
        AuthenticationManager.shared.stopFaceAuth()
        UserDefaults.standard.set(false, forKey: FGConstants.protectionDisabledKey)
        UserDefaults.standard.removeObject(forKey: FGConstants.protectionDisableExpiryKey)
    }

    // MARK: - Settings Window

    private func closeMenuBarWindow() {
        statusItem?.menu?.cancelTracking()
        
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("StatusItem") || className.contains("MenuWindow") || (window.title.isEmpty && window.isVisible && className.contains("Window")) {
                window.close()
            }
        }
    }

    @MainActor
    @objc private func showSettingsWindow() {
        SettingsWindowController.show()
    }

    @MainActor
    @objc private func openSettingsWindow() {
        closeMenuBarWindow()

        if SettingsWindowController.isVisible {
            SettingsWindowController.show()
            return
        }

        ActionAuthWindow.show(reason: "FaceGate Settings") {
            Task { @MainActor in
                SettingsWindowController.show()
            }
        }
    }

    @objc private func openSetupWindow() {
        closeMenuBarWindow()

        if let existing = setupWindow {
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let setupView = SetupView(
            onSetupComplete: {
                AppMonitor.shared.startMonitoring()
                // Find and close the setup window
                for window in NSApp.windows {
                    if window.title == "FaceGate Setup" {
                        window.close()
                    }
                }
            },
            onOpenSettings: {
                AppMonitor.shared.startMonitoring()
                // Close the setup window
                for window in NSApp.windows {
                    if window.title == "FaceGate Setup" {
                        window.close()
                    }
                }
                // Open settings window
                NotificationCenter.default.post(name: Notification.Name.openSettings, object: nil)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FaceGate Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: setupView)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let x = screen.frame.origin.x + (screen.frame.width - window.frame.width) / 2
            let y = screen.frame.origin.y + (screen.frame.height - window.frame.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == setupWindow {
            setupWindow = nil
            // Optionally, post a notification to tell FaceEnrollmentView to explicitly cancel
            NotificationCenter.default.post(name: NSNotification.Name("SetupWindowWillClose"), object: nil)
        }
    }

    // MARK: - Sleep / Lock Handling

    @objc private func systemWillSleep() {
        guard UserDefaults.standard.bool(forKey: FGConstants.lockOnSleepKey) else { return }
        SessionManager.shared.revokeAllSessions()
    }

    private func syncUninstallProtection() {
        let shouldProtect = UserDefaults.standard.bool(forKey: FGConstants.uninstallProtectionKey)
        let bundleURL = Bundle.main.bundleURL
        
        do {
            let resourceValues = try bundleURL.resourceValues(forKeys: [.isUserImmutableKey])
            let currentImmutable = resourceValues.isUserImmutable ?? false
            if currentImmutable != shouldProtect {
                try? (bundleURL as NSURL).setResourceValue(shouldProtect, forKey: .isUserImmutableKey)
                print("[FaceGate] Synced bundle immutable state to \(shouldProtect).")
            }
        } catch {
            print("[FaceGate] Failed to sync uninstall protection on launch: \(error)")
        }
    }
    
    // MARK: - Custom Menu Bar
    
    @MainActor
    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let icon = NSImage(named: FGConstants.menuBarIcon)
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(menuBarButtonClicked(_:))
            button.target = self
        }
        
        let builder = MenuBuilder()
        self.menuBuilder = builder
        
        // Setup Popover for Classic Theme
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ClassicMenuBarView())
        self.classicPopover = popover
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.classicPopover, popover.isShown {
                popover.performClose(event)
            }
        }
    }
    
    @MainActor
    @objc private func menuBarButtonClicked(_ sender: NSStatusBarButton) {
        let themeRaw = UserDefaults.standard.string(forKey: FGConstants.appThemeKey) ?? AppTheme.classic.rawValue
        let theme = AppTheme(rawValue: themeRaw) ?? .classic
        
        if theme == .classic {
            if let popover = classicPopover {
                if popover.isShown {
                    popover.performClose(sender)
                } else {
                    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
                    popover.contentViewController?.view.window?.makeKey()
                }
            }
        } else {
            if let menu = menuBuilder?.buildMenu() {
                statusItem?.menu = menu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil // Reset so we intercept next click
            }
        }
    }
}

// MARK: - Sparkle Updater Delegate

extension AppDelegate: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain,
              nsError.code == 4012,
              UserDefaults.standard.bool(forKey: FGConstants.uninstallProtectionKey) else { return }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Update Failed — Uninstall Protection Is On"
            alert.informativeText = "FaceGate's uninstall protection prevents the app bundle from being modified. To update, disable Uninstall Protection in Settings → Advanced, then check for updates again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
