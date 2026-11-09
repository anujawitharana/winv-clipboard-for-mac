import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var expireTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply saved appearance if any
        let mode = UserDefaults.standard.string(forKey: "WinVAppearanceMode") ?? "system"
        if mode == "light" {
            NSApp.appearance = NSAppearance(named: .aqua)
        } else if mode == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        // Initialize Store & Services
        _ = ClipboardStore.shared

        // Start Clipboard Monitor
        ClipboardMonitor.shared.start()

        // Setup Carbon Hotkey
        HotkeyManager.shared.onHotKeyTriggered = {
            PanelController.shared.toggle()
        }
        HotkeyManager.shared.start()

        // Setup System Menu Bar Tray
        StatusItemManager.shared.setup()

        // Non-blocking background update check on launch (respects 24h interval & user setting)
        Task { @MainActor in
            await UpdateManager.shared.checkForUpdates(isUserInitiated: false)
            if UpdateManager.shared.availableRelease != nil {
                StatusItemManager.shared.rebuildMenu()
            }
        }

        // Periodic auto-expire check every 15 minutes
        expireTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            let hours = UserDefaults.standard.integer(forKey: "WinVAutoExpireHours")
            if hours > 0 {
                Task { @MainActor in
                    ClipboardStore.shared.purgeOlderThan(hours: hours)
                }
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        expireTimer?.invalidate()
    }
}
