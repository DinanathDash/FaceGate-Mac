import SwiftUI
import AppKit

struct ClassicLockedAppsSettingsView: View {
    @ObservedObject var lockedAppsManager = LockedAppsManager.shared
    @State private var showingAddApps = false
    @State private var installedApps: [InstalledAppsScanner.DiscoveredApp] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var filteredLockedApps: [LockedApp] {
        if searchText.isEmpty {
            return lockedAppsManager.lockedApps
        }
        return lockedAppsManager.lockedApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredUnlockedApps: [InstalledAppsScanner.DiscoveredApp] {
        let lockedBundleIDs = Set(lockedAppsManager.lockedApps.map { $0.bundleIdentifier })
        let unlocked = installedApps.filter { !lockedBundleIDs.contains($0.bundleIdentifier) }
        if searchText.isEmpty {
            return unlocked
        }
        return unlocked.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if showingAddApps {
                    addAppsHeader
                    Divider()
                    if isLoading {
                        loadingView
                    } else if filteredUnlockedApps.isEmpty {
                        emptyUnlockedView
                    } else {
                        unlockedAppsList
                    }
                } else {
                    lockedAppsHeader
                    Divider()
                    if lockedAppsManager.lockedApps.isEmpty {
                        emptyLockedView
                    } else if filteredLockedApps.isEmpty {
                        noSearchResultsView
                    } else {
                        VStack(spacing: 0) {
                            Text("Click an app to customize its session timer")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            lockedAppsList
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .onAppear {
                loadAppsIfNeeded()
            }
            .onDisappear {
                installedApps = []
            }
            .navigationDestination(for: LockedApp.self) { app in
                LockedAppDetailView(app: app, path: $path)
            }
        }
    }

    // MARK: - Loading State View
    @ViewBuilder
    private var loadingView: some View {
        Spacer()
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Scanning installed apps…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        Spacer()
    }

    // MARK: - Empty States
    @ViewBuilder
    private var emptyLockedView: some View {
        Spacer()
        VStack(spacing: 16) {
            Image(systemName: "lock.open")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            VStack(spacing: 4) {
                Text("No Apps Locked")
                    .font(.system(size: 14, weight: .semibold))
                Text("Protect your apps by adding them to the lock list.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 260)
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchText = ""
                    showingAddApps = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Apps")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        Spacer()
    }

    @ViewBuilder
    private var emptyUnlockedView: some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green.opacity(0.8))
            VStack(spacing: 4) {
                Text("All Apps Locked")
                    .font(.system(size: 14, weight: .semibold))
                Text("You've locked all discovered applications on this system.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 260)
        }
        Spacer()
    }

    @ViewBuilder
    private var noSearchResultsView: some View {
        Spacer()
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("No results matching \"\(searchText)\"")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        Spacer()
    }

    // MARK: - Headers
    private var lockedAppsHeader: some View {
        HStack(spacing: 12) {
            Text("Locked Apps")
                .font(.system(size: 15, weight: .bold))

            Spacer()

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 160)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchText = ""
                    showingAddApps = true
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Apps…")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var addAppsHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchText = ""
                    showingAddApps = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Done")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Text("Add Apps to Lock")
                .font(.system(size: 15, weight: .bold))

            Spacer()

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Lists
    private var lockedAppsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredLockedApps, id: \.bundleIdentifier) { app in
                    LockedRowView(app: app, onToggle: {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.8, blendDuration: 0)) {
                            lockedAppsManager.unlockApp(app.bundleIdentifier)
                        }
                    }, onClick: {
                        path.append(app)
                    })
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .scale(scale: 0.7).combined(with: .opacity)
                    ))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var unlockedAppsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(filteredUnlockedApps, id: \.bundleIdentifier) { app in
                    UnlockedRowView(app: app) {
                        let startTime = Date()
                        DispatchQueue.global(qos: .userInitiated).async {
                            let lockedApp = InstalledAppsScanner.shared.toLockedApp(app, isLocked: true)
                            let elapsed = Date().timeIntervalSince(startTime)
                            let remainingDelay = max(0, 0.20 - elapsed)
                            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.8, blendDuration: 0)) {
                                    lockedAppsManager.lockApp(lockedApp)
                                }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .scale(scale: 0.7).combined(with: .opacity)
                    ))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Private Helpers
    private func loadAppsIfNeeded() {
        guard installedApps.isEmpty else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = InstalledAppsScanner.shared.scanInstalledApps()
            DispatchQueue.main.async {
                installedApps = apps
                isLoading = false
            }
        }
    }
}

// MARK: - Individual Row Views

private struct LockedRowView: View {
    let app: LockedApp
    let onToggle: () -> Void
    let onClick: () -> Void
    @State private var isLocked = true
    @State private var isHovered = false
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        
                        if app.customSessionTimeout != nil {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                    Text(app.bundleIdentifier)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onClick()
            }

            Toggle("", isOn: $isLocked)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .allowsHitTesting(!isProcessing)
                .onChangeCompat(of: isLocked) { newValue in
                    guard !isProcessing else { return }
                    if !newValue {
                        isProcessing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onToggle()
                        }
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct UnlockedRowView: View {
    let app: InstalledAppsScanner.DiscoveredApp
    let onToggle: () -> Void
    @State private var isLocked = false
    @State private var isHovered = false
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $isLocked)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .allowsHitTesting(!isProcessing)
                .onChangeCompat(of: isLocked) { newValue in
                    guard !isProcessing else { return }
                    if newValue {
                        isProcessing = true
                        onToggle()
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct LockedAppDetailView: View {
    let app: LockedApp
    @Binding var path: NavigationPath
    
    @ObservedObject var lockedAppsManager = LockedAppsManager.shared
    
    @State private var hasCustomTimer = false
    @State private var customTimeoutMinutes: Double = 5
    @State private var appTimerMode: Int = 0 // 0=global, 1=fromUnlock, 2=fromFocus
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Back Button
            HStack {
                Button(action: {
                    path.removeLast()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(app.displayName)
                    .font(.system(size: 14, weight: .bold))
                
                Spacer()
                
                // Placeholder to balance the back button
                Text("Back")
                    .font(.system(size: 13))
                    .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 48, height: 48)
                            } else {
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 48, height: 48)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                Text(app.bundleIdentifier)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Divider()
                        
                        // Custom session timer configurations
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Toggle("Custom Session Timer", isOn: $hasCustomTimer)
                                    .toggleStyle(.checkbox)
                                
                                Spacer()
                                
                                if hasCustomTimer {
                                    if customTimeoutMinutes == FGConstants.indefiniteSliderValue {
                                        Text("Keep Unlocked Indefinitely")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.blue)
                                    } else if customTimeoutMinutes == 0 {
                                        Text("Lock Immediately")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.blue)
                                    } else {
                                        Text("\(Int(customTimeoutMinutes)) min")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                } else {
                                    let globalTimeout = SessionManager.shared.sessionTimeout / 60
                                    if globalTimeout == 0 {
                                        Text("Using Global Timer (Lock Immediately)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Using Global Timer (\(Int(globalTimeout)) min)")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Slider(value: $customTimeoutMinutes, in: 0...FGConstants.indefiniteSliderValue, step: 1)
                                    .disabled(!hasCustomTimer)
                                
                                Text("0-31m")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .opacity(hasCustomTimer ? 1.0 : 0.5)

                            if hasCustomTimer && customTimeoutMinutes > 0 && customTimeoutMinutes < FGConstants.indefiniteSliderValue {
                                Picker("Timer Mode", selection: $appTimerMode) {
                                    Text("Use Global Setting").tag(0)
                                    Text("From last unlock").tag(1)
                                    Text("From when app loses focus").tag(2)
                                }
                                .pickerStyle(.menu)
                                switch appTimerMode {
                                case 1:
                                    Text("The timer counts total elapsed time since unlock, regardless of whether you're actively using the app.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                case 2:
                                    Text("The timer only counts down while the app is not in focus. Switch away for the full duration to trigger a lock.")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                default:
                                    let globalMode = UserDefaults.standard.bool(forKey: FGConstants.sessionTimerFromFocusKey)
                                    if globalMode {
                                        Text("Using global: timer counts from when app loses focus.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Using global: timer counts total elapsed time since unlock.")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let activeApp = lockedAppsManager.lockedApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                if let custom = activeApp.customSessionTimeout {
                    hasCustomTimer = true
                    customTimeoutMinutes = custom == FGConstants.indefiniteSessionValue ? FGConstants.indefiniteSliderValue : custom / 60
                } else {
                    hasCustomTimer = false
                    // Restore last selection from UserDefaults if available, otherwise default to 5
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
        // Revoke existing session so the new timeout takes effect immediately.
        SessionManager.shared.revokeSession(for: app.bundleIdentifier)
    }
}
