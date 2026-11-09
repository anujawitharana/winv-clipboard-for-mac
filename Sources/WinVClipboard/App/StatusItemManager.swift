import Foundation
import AppKit

@MainActor
public final class StatusItemManager {
    public static let shared = StatusItemManager()

    private var statusItem: NSStatusItem?

    private init() {}

    public func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "WinV Clipboard")
            button.image?.isTemplate = true
        }

        rebuildMenu()
    }

    public func rebuildMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()

        let shortcutDisplay = HotkeyManager.shared.activeShortcut.displayString

        let showItem = NSMenuItem(title: "Show Clipboard (\(shortcutDisplay))", action: #selector(handleShowClipboard), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let isPaused = PrivacyFilter.shared.isMonitoringPaused
        let pauseItem = NSMenuItem(title: isPaused ? "Resume Monitoring" : "Pause Monitoring", action: #selector(handleTogglePause), keyEquivalent: "")
        pauseItem.state = isPaused ? .on : .off
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(NSMenuItem.separator())

        if let release = UpdateManager.shared.availableRelease {
            let updateNoticeItem = NSMenuItem(title: "Update Available: v\(release.version)", action: #selector(handleOpenAbout), keyEquivalent: "")
            updateNoticeItem.target = self
            updateNoticeItem.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(updateNoticeItem)
        }

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(handleOpenPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(title: "About WinV Clipboard", action: #selector(handleOpenAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let updateCheckItem = NSMenuItem(title: "Check for Updates...", action: #selector(handleCheckForUpdates), keyEquivalent: "")
        updateCheckItem.target = self
        menu.addItem(updateCheckItem)

        let isTrusted = PasteInjector.isAccessibilityTrusted
        let permItem = NSMenuItem(title: isTrusted ? "Accessibility: Active" : "Accessibility: Required (Click to Grant)", action: #selector(handleCheckPermissions), keyEquivalent: "")
        permItem.target = self
        permItem.image = NSImage(systemSymbolName: isTrusted ? "checkmark.circle" : "exclamationmark.triangle", accessibilityDescription: nil)
        menu.addItem(permItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit WinV Clipboard", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func handleShowClipboard() {
        PanelController.shared.toggle()
    }

    @objc private func handleTogglePause() {
        PrivacyFilter.shared.isMonitoringPaused.toggle()
        rebuildMenu()
    }

    @objc private func handleOpenPreferences() {
        SettingsWindowController.shared.show(tab: .general)
    }

    @objc private func handleOpenAbout() {
        SettingsWindowController.shared.show(tab: .about)
    }

    @objc private func handleCheckForUpdates() {
        SettingsWindowController.shared.show(tab: .about)
        Task { @MainActor in
            await UpdateManager.shared.checkForUpdates(isUserInitiated: true)
            self.rebuildMenu()
        }
    }

    @objc private func handleCheckPermissions() {
        if !PasteInjector.isAccessibilityTrusted {
            PasteInjector.promptForAccessibility()
        }
        SettingsWindowController.shared.show(tab: .permissions)
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
