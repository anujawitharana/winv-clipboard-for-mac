import SwiftUI
import AppKit

@MainActor
public struct SettingsView: View {
    @ObservedObject var controller: SettingsWindowController
    @ObservedObject private var updateManager = UpdateManager.shared
    @AppStorage("WinVAutoCheckUpdates") private var isAutoCheckEnabled: Bool = true
    @AppStorage("WinVMaxHistory") private var maxHistory: Int = 50
    @AppStorage("WinVAutoExpireHours") private var autoExpireHours: Int = 0
    @AppStorage("WinVAppearanceMode") private var appearanceMode: String = "system"
    @State private var isMonitoringPaused: Bool = PrivacyFilter.shared.isMonitoringPaused
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var isAccessibilityTrusted: Bool = PasteInjector.isAccessibilityTrusted

    public init(controller: SettingsWindowController) {
        self.controller = controller
    }

    public init() {
        self.controller = .shared
    }

    public var body: some View {
        TabView(selection: $controller.selectedTab) {
            // General Tab
            Form {
                Section("Global Shortcut") {
                    HStack {
                        Text("Open Clipboard Flyout:")
                        Spacer()
                        ShortcutRecorderView()
                    }
                    Text("Default: ⌥V (Option + V), identical ergonomics to Windows Win+V.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Section("Application Behavior") {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            LaunchAtLoginService.setEnabled(newValue)
                        }
                    ))

                    Toggle("Pause Clipboard Monitoring", isOn: Binding(
                        get: { isMonitoringPaused },
                        set: { newValue in
                            isMonitoringPaused = newValue
                            PrivacyFilter.shared.isMonitoringPaused = newValue
                        }
                    ))
                    if isMonitoringPaused {
                        Text("Monitoring is currently paused. No new copies will be saved.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }

                    Picker("Appearance", selection: $appearanceMode) {
                        Text("Match System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .onChange(of: appearanceMode) { _, mode in
                        updateAppearance(mode)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            .tag(SettingsTab.general)

            // History & Storage Tab
            Form {
                Section("History Limits") {
                    Stepper(value: $maxHistory, in: 10...500, step: 10) {
                        HStack {
                            Text("Max Unpinned History:")
                            Spacer()
                            Text("\(maxHistory) clips")
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Auto-Clear Unpinned History After:", selection: $autoExpireHours) {
                        Text("Never").tag(0)
                        Text("1 Hour").tag(1)
                        Text("24 Hours").tag(24)
                        Text("7 Days").tag(168)
                        Text("30 Days").tag(720)
                    }

                    Text("Pinned items are permanently protected and will never be auto-cleared or pruned.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Section("Actions") {
                    Button(role: .destructive, action: {
                        ClipboardStore.shared.clearAllUnpinned()
                    }) {
                        Text("Clear All Unpinned History Now")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Storage", systemImage: "internaldrive")
            }
            .tag(SettingsTab.storage)

            // Privacy Tab
            VStack(alignment: .leading, spacing: 14) {
                ExclusionListView()

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy & Security Notice")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("WinV Clipboard operates 100% locally on your Mac. All clips and images remain inside ~/Library/Application Support/WinVClipboard/ and are never sent over the network. We automatically detect standard concealed clipboard markers (org.nspasteboard.ConcealedType) and known password managers. However, because macOS sandboxing does not expose arbitrary application text-input classifications, best-effort detection is applied. Sensitive applications should be added to the exclusion list above.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .tabItem {
                Label("Privacy", systemImage: "hand.raised")
            }
            .tag(SettingsTab.privacy)

            // Permissions Tab
            Form {
                Section("Accessibility Permissions") {
                    HStack(spacing: 12) {
                        Image(systemName: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isAccessibilityTrusted ? .green : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isAccessibilityTrusted ? "Accessibility Permission Granted" : "Accessibility Permission Required for Auto-Paste")
                                .font(.system(size: 13, weight: .medium))

                            Text("When you select an item from the clipboard flyout, WinV simulates ⌘V to paste it directly into your active application. This requires Accessibility access.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if !isAccessibilityTrusted {
                        Button("Open System Settings to Grant Permission") {
                            PasteInjector.promptForAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isAccessibilityTrusted = PasteInjector.isAccessibilityTrusted
                            }
                        }
                    } else {
                        Text("Auto-paste is fully operational.")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }

                Section("Full Disk Access (Optional, Recommended)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seamless File & Image Copying Without Folder Prompts")
                            .font(.system(size: 13, weight: .medium))

                        Text("macOS asks for permission when reading files from Desktop, Downloads, or Documents. Granting Full Disk Access allows WinV Clipboard to preview and paste images copied from any folder without ever prompting you.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Button("Open Full Disk Access Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Permissions", systemImage: "lock.shield")
            }
            .tag(SettingsTab.permissions)

            // About Tab
            VStack(spacing: 12) {
                Spacer(minLength: 8)

                // Header Brand
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color(red: 0.05, green: 0.6, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.blue.opacity(0.35), radius: 8, x: 0, y: 4)

                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Text("WinV Clipboard")
                        .font(.system(size: 18, weight: .bold))

                    Text("Version 1.0.0 (Build 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)

                    Text("Native Windows 11 Clipboard (Win + V) for macOS")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(maxWidth: 340)
                    .opacity(0.4)

                // Author & Action Buttons
                VStack(spacing: 10) {
                    Text("Created by Anuja Witharana")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 12) {
                        Button(action: {
                            if let url = URL(string: "https://github.com/anujawitharana") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle")
                                Text("GitHub Profile")
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)

                        Button(action: {
                            if let url = URL(string: "https://github.com/anujawitharana/winv-clipboard-for-mac") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                Text("Repository")
                            }
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    // Links Row
                    HStack(spacing: 12) {
                        Button(action: {
                            if let url = URL(string: "https://github.com/anujawitharana/winv-clipboard-for-mac") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("Star on GitHub")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.link)

                        Text("•")
                            .foregroundColor(.secondary.opacity(0.4))
                            .font(.system(size: 11))

                        Button(action: {
                            if let url = URL(string: "https://github.com/anujawitharana/winv-clipboard-for-mac/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "ladybug")
                                Text("Report an Issue")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.link)

                        Text("•")
                            .foregroundColor(.secondary.opacity(0.4))
                            .font(.system(size: 11))

                        Button(action: {
                            OnboardingWindowController.shared.show(initialStep: 1)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.wave")
                                Text("Setup Guide")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                    }
                }

                Divider()
                    .frame(maxWidth: 340)
                    .opacity(0.4)

                // Updates Status Line & Toggle
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        switch updateManager.status {
                        case .idle:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("WinV Clipboard 1.0.0 is up to date.")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                            Button("Check Again") {
                                Task { await updateManager.checkForUpdates(isUserInitiated: true) }
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))

                        case .checking:
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking GitHub for updates...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                        case .upToDate(let version):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("WinV Clipboard \(version) is up to date.")
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                            Button("Check Again") {
                                Task { await updateManager.checkForUpdates(isUserInitiated: true) }
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))

                        case .updateAvailable(let release):
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("Version \(release.version) is available!")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                            Button("Install & Relaunch") {
                                Task { await updateManager.downloadAndInstall(release: release) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        case .downloading(let progress):
                            ProgressView(value: progress)
                                .frame(width: 90)
                            Text("Downloading (\(Int(progress * 100))%)...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                        case .extracting, .readyToRestart:
                            ProgressView()
                                .controlSize(.small)
                            Text("Relaunching WinV Clipboard...")
                                .font(.system(size: 11))
                                .foregroundColor(.green)

                        case .error:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Check failed")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task { await updateManager.checkForUpdates(isUserInitiated: true) }
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                        }
                    }

                    Toggle("Automatically check for updates on startup", isOn: $isAutoCheckEnabled)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .toggleStyle(.checkbox)
                        .onChange(of: isAutoCheckEnabled) { _, newValue in
                            updateManager.isAutoCheckEnabled = newValue
                        }
                }

                Spacer(minLength: 12)

                // Footer
                Text("MIT License © 2026 Anuja Witharana. Free and Open Source.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 480)
        .onAppear {
            isAccessibilityTrusted = PasteInjector.isAccessibilityTrusted
            launchAtLogin = LaunchAtLoginService.isEnabled
            isMonitoringPaused = PrivacyFilter.shared.isMonitoringPaused
        }
    }

    private func updateAppearance(_ mode: String) {
        switch mode {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
