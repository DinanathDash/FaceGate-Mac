import AppKit
import ServiceManagement
import SwiftUI

final class SettingsChromeState: ObservableObject {
    @Published var isSidebarCollapsed = false
}

/// The main settings window with tabbed navigation.
struct ClassicSettingsView: View {
    @ObservedObject var lockedAppsManager = LockedAppsManager.shared
    @ObservedObject var chromeState: SettingsChromeState

    @AppStorage("lastSelectedSettingsTab") private var selectedTab: SettingsTab = .lockedApps

    init(chromeState: SettingsChromeState = SettingsChromeState()) {
        self.chromeState = chromeState
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case lockedApps = "Locked Apps"
        case authentication = "Authentication"
        case behavior = "Behavior"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .lockedApps: return "lock.app.dashed"
            case .authentication: return "person.badge.key.fill"
            case .behavior: return "gearshape.2.fill"
            case .about: return "info.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .lockedApps: return "Choose which apps require authentication."
            case .authentication: return "Tune Face Unlock, Touch ID, and password fallback."
            case .behavior: return "Adjust launch, locking, schedules, and emergency controls."
            case .about: return "Version, license, and project details."
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.codexWindowBackground
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if !chromeState.isSidebarCollapsed {
                    CodexSettingsSidebar(selectedTab: $selectedTab)
                        .frame(width: 220)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                SettingsDetailPane(selectedTab: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: chromeState.isSidebarCollapsed)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        chromeState.isSidebarCollapsed.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
        }
    }
}

private struct CodexSettingsSidebar: View {
    @Binding var selectedTab: ClassicSettingsView.SettingsTab
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPermissions = false
    @State private var showResetConfirmation = false
    @State private var showThemePicker = false
    @AppStorage(FGConstants.appThemeKey) private var currentThemeRaw = AppTheme.classic.rawValue

    private var currentTheme: AppTheme {
        get { AppTheme(rawValue: currentThemeRaw) ?? .classic }
        set { currentThemeRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            CodexSidebarVisualEffect(material: .sidebar, blendingMode: .behindWindow)

            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.30, green: 0.32, blue: 0.42).opacity(0.36),
                        Color(red: 0.12, green: 0.22, blue: 0.22).opacity(0.30),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FaceGate")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Settings")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 34)
                .padding(.horizontal, 18)
                .padding(.bottom, 20)

                Text("Preferences")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)

                VStack(spacing: 3) {
                    ForEach(ClassicSettingsView.SettingsTab.allCases) { tab in
                        CodexSidebarRow(
                            tab: tab,
                            isSelected: selectedTab == tab
                        ) {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.horizontal, 8)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { showThemePicker = true }) {
                        Image(systemName: "paintbrush.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
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
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
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
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Reset App")
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
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
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
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

private struct CodexSidebarRow: View {
    let tab: ClassicSettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .symbolRenderingMode(.hierarchical)

                Text(tab.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.70))
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.11))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct SettingsDetailPane: View {
    let selectedTab: ClassicSettingsView.SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(selectedTab.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.top, 34)
            .padding(.bottom, 18)

            Divider()
                .overlay(Color.primary.opacity(0.07))

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.codexWindowBackground)
        }
        .background(Color.codexWindowBackground)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .lockedApps:
            ClassicLockedAppsSettingsView()
        case .authentication:
            AuthSettingsView()
        case .behavior:
            BehaviorSettingsView()
        case .about:
            AboutView()
        }
    }
}

private struct CodexSidebarVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

private extension Color {
    static let codexWindowBackground = Color(nsColor: .windowBackgroundColor)
}

