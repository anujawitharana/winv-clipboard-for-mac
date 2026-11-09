import Foundation
import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: ObservableObject {
    public static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private init() {}

    public func show(initialStep: Int? = nil) {
        if let step = initialStep {
            UserDefaults.standard.set(step, forKey: "WinVOnboardingCurrentStep")
        }

        if let window = window {
            let onboardingView = OnboardingView(initialStep: initialStep, onComplete: { [weak self] in
                self?.close()
                // Open the flyout immediately for the user to try out!
                PanelController.shared.toggle()
            })
            window.contentView = NSHostingView(rootView: onboardingView)
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

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.orderOut(nil)
        window = nil
    }
}
