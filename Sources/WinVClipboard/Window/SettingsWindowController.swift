import Foundation
import AppKit
import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case storage
    case privacy
    case permissions
    case about

    public var id: String { rawValue }
}

@MainActor
public final class SettingsWindowController: ObservableObject {
    public static let shared = SettingsWindowController()

    @Published public var selectedTab: SettingsTab = .general
    private var window: NSWindow?

    private init() {}

    public func show(tab: SettingsTab = .general) {
        self.selectedTab = tab
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(controller: self)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "WinV Clipboard Settings"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
