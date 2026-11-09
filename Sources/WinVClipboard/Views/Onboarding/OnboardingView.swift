import SwiftUI
import AppKit
import Combine

public struct OnboardingView: View {
    public let onComplete: () -> Void

    @State private var currentStep: Int
    @State private var isAccessibilityGranted: Bool = PasteInjector.isAccessibilityTrusted
    @State private var isFullDiskAccessGranted: Bool = PasteInjector.isFullDiskAccessGranted
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @AppStorage("WinVAutoCheckUpdates") private var autoCheckUpdates: Bool = true

    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    public init(initialStep: Int? = nil, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let step: Int
        if let explicit = initialStep, explicit >= 1 && explicit <= 3 {
            step = explicit
        } else {
            let saved = UserDefaults.standard.integer(forKey: "WinVOnboardingCurrentStep")
            step = (saved >= 1 && saved <= 3) ? saved : 1
        }
        _currentStep = State(initialValue: step)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Indicator
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { step in
                    Capsule()
                        .fill(step == currentStep ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: step == currentStep ? 24 : 8, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            // Content per step
            Group {
                switch currentStep {
                case 1:
                    welcomeStepView
                case 2:
                    permissionsStepView
                case 3:
                    preferencesStepView
                default:
                    welcomeStepView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .opacity(0.3)

            // Bottom Action Bar
            HStack {
                if currentStep > 1 {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Spacer()

                if currentStep < 3 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(currentStep == 1 ? "Get Started" : "Continue")
                            Image(systemName: "arrow.right")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else {
                    Button(action: {
                        finishOnboarding()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Finish & Open Clipboard")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 560, height: 530)
        .onReceive(timer) { _ in
            if currentStep == 2 {
                isAccessibilityGranted = PasteInjector.isAccessibilityTrusted
                isFullDiskAccessGranted = PasteInjector.isFullDiskAccessGranted
            }
        }
        .onChange(of: currentStep) { _, newStep in
            UserDefaults.standard.set(true, forKey: "WinVOnboardingInProgress")
            UserDefaults.standard.set(newStep, forKey: "WinVOnboardingCurrentStep")
        }
        .onAppear {
            let saved = UserDefaults.standard.integer(forKey: "WinVOnboardingCurrentStep")
            if saved >= 1 && saved <= 3 {
                currentStep = saved
            }
            UserDefaults.standard.set(true, forKey: "WinVOnboardingInProgress")
            UserDefaults.standard.set(currentStep, forKey: "WinVOnboardingCurrentStep")
            isAccessibilityGranted = PasteInjector.isAccessibilityTrusted
            isFullDiskAccessGranted = PasteInjector.isFullDiskAccessGranted
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
    }

    // MARK: - Step 1: Welcome View
    private var welcomeStepView: some View {
        VStack(spacing: 16) {
            Spacer()

            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.05, green: 0.6, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.blue.opacity(0.35), radius: 10, x: 0, y: 5)

                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text("Welcome to WinV Clipboard")
                    .font(.system(size: 22, weight: .bold))

                Text("The fluid, native Windows 11 Clipboard History experience for macOS.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureBullet(
                    icon: "command",
                    iconColor: .blue,
                    title: "Global Shortcut: ⌥V (Option + V)",
                    description: "Press Option + V anywhere to invoke your floating clipboard history."
                )

                featureBullet(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "Direct Auto-Paste",
                    description: "Press Enter or click any clip to paste it directly into your active application."
                )

                featureBullet(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "100% Offline & Private",
                    description: "Stored exclusively in local SQLite. Password managers are automatically excluded."
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 2: Permissions View
    private var permissionsStepView: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)

            VStack(spacing: 4) {
                Text("System Permissions")
                    .font(.system(size: 20, weight: .bold))

                Text("Grant the permissions below for seamless auto-pasting and photo copying.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Card 1: Accessibility
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: isAccessibilityGranted ? "checkmark.circle.fill" : "command.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isAccessibilityGranted ? .green : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Accessibility")
                                .font(.system(size: 13, weight: .semibold))
                            Text("(Required for Auto-Paste)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Text(isAccessibilityGranted
                            ? "Permission active. WinV can paste directly with ⌘V."
                            : "Simulates paste keystrokes into your target apps.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isAccessibilityGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .padding(6)
                            .background(Circle().fill(Color.green.opacity(0.12)))
                    }
                }

                if !isAccessibilityGranted {
                    Button(action: {
                        PasteInjector.promptForAccessibility()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text("Grant Accessibility Permission")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isAccessibilityGranted ? Color.green.opacity(0.06) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isAccessibilityGranted ? Color.green.opacity(0.2) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // Card 2: Full Disk Access
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: isFullDiskAccessGranted ? "checkmark.circle.fill" : "internaldrive.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isFullDiskAccessGranted ? .green : .indigo)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Full Disk Access")
                                .font(.system(size: 13, weight: .semibold))
                            Text("(Recommended for Images)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Text(isFullDiskAccessGranted
                            ? "Permission active. Images copy without folder prompts."
                            : "Previews and pastes images from Desktop, Downloads & Documents.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isFullDiskAccessGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                            .padding(6)
                            .background(Circle().fill(Color.green.opacity(0.12)))
                    }
                }

                if !isFullDiskAccessGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            PasteInjector.promptForFullDiskAccess()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Open Full Disk Access Settings")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                                .padding(.top, 1)

                            Text("When enabled, macOS asks to \"Quit & Reopen\". You can click **Later** to finish setup now, or click **Quit & Reopen** and WinV Clipboard will resume right here.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFullDiskAccessGranted ? Color.green.opacity(0.06) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFullDiskAccessGranted ? Color.green.opacity(0.2) : Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Text("Permissions update automatically as soon as enabled in macOS System Settings.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 3: Preferences View
    private var preferencesStepView: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 6) {
                Text("Customize Your Workflow")
                    .font(.system(size: 20, weight: .bold))

                Text("Configure your default options below. You can change these anytime in Preferences.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                // Hotkey Card
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Global Shortcut")
                            .font(.system(size: 13, weight: .medium))
                        Text("Default: ⌥V (Option + V)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorderView()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )

                // Launch at Login Card
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        LaunchAtLoginService.setEnabled(newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                        Text("Start WinV Clipboard automatically when your Mac boots.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )

                // Automatic Updates Card
                Toggle(isOn: $autoCheckUpdates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically Check for Updates")
                            .font(.system(size: 13, weight: .medium))
                        Text("Silently checks GitHub Releases once a day for bug fixes and new features.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helper Views
    private func featureBullet(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func finishOnboarding() {
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingInProgress")
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingCurrentStep")
        UserDefaults.standard.set(true, forKey: "WinVHasCompletedOnboarding")
        onComplete()
    }
}
