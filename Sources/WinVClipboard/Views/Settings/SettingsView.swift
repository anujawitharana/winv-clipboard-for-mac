import SwiftUI
import AppKit

public struct SettingsView: View {
    @AppStorage("WinVMaxHistory") private var maxHistory: Int = 50
    @AppStorage("WinVAutoExpireHours") private var autoExpireHours: Int = 0
    @AppStorage("WinVAppearanceMode") private var appearanceMode: String = "system"
    @State private var isMonitoringPaused: Bool = PrivacyFilter.shared.isMonitoringPaused
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var isAccessibilityTrusted: Bool = PasteInjector.isAccessibilityTrusted

    public init() {}

    public var body: some View {
        TabView {
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
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Permissions", systemImage: "lock.shield")
            }
        }
        .frame(width: 520, height: 420)
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
}
