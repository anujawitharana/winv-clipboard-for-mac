import Foundation
import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    public func show(initialStep: Int? = nil) {
        UserDefaults.standard.set(true, forKey: "WinVOnboardingInProgress")

        if let step = initialStep {
            UserDefaults.standard.set(step, forKey: "WinVOnboardingCurrentStep")
        } else if UserDefaults.standard.integer(forKey: "WinVOnboardingCurrentStep") == 0 {
            UserDefaults.standard.set(1, forKey: "WinVOnboardingCurrentStep")
        }

        if let window = window {
            let onboardingView = OnboardingView(initialStep: initialStep, onComplete: { [weak self] in
                self?.close()
                // Open the flyout immediately for the user to try out!
                PanelController.shared.toggle()
            })
            window.contentView = NSHostingView(rootView: onboardingView)
            window.level = .floating
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(initialStep: initialStep, onComplete: { [weak self] in
            self?.close()
            // Open the flyout immediately for the user to try out!
            PanelController.shared.toggle()
        })
        let hostingView = NSHostingView(rootView: onboardingView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 530),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to WinV Clipboard"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.delegate = self

        self.window = window
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingInProgress")
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingCurrentStep")
        window?.orderOut(nil)
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingInProgress")
        UserDefaults.standard.removeObject(forKey: "WinVOnboardingCurrentStep")
        UserDefaults.standard.set(true, forKey: "WinVHasCompletedOnboarding")
        window = nil
    }
}
