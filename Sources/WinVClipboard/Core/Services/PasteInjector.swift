import Foundation
import AppKit
import Carbon

public final class PasteInjector: @unchecked Sendable {
    public static let shared = PasteInjector()

    private init() {}

    /// Injects paste into the target application.
    @MainActor
    public func pasteItem(
        _ item: ClipboardItem,
        targetApp: NSRunningApplication?,
        onComplete: (() -> Void)? = nil
    ) {
        let store = ClipboardStore.shared

        // 1. Put item onto pasteboard with internal restoration flag set
        ClipboardMonitor.shared.isInternalRestoration = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(Data([1]), forType: ClipboardMonitor.internalRestorationType)

        switch item.contentType {
        case .image:
            if let relPath = item.imageRelativePath, let imgData = store.fullImageData(for: relPath) {
                pasteboard.setData(imgData, forType: .png)
                if let nsImage = NSImage(data: imgData), let tiff = nsImage.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            } else if let path = item.plainText, FileManager.default.fileExists(atPath: path) {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
                    pasteboard.setData(data, forType: .png)
                    if let img = NSImage(data: data), let tiff = img.tiffRepresentation {
                        pasteboard.setData(tiff, forType: .tiff)
                    }
                } else if let fileImg = NSImage(contentsOfFile: path), let tiff = fileImg.tiffRepresentation {
                    if let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        pasteboard.setData(png, forType: .png)
                    }
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }

            // Only supply file URL if target application is Finder (for file copying/moving in folders)
            if targetApp?.bundleIdentifier == "com.apple.finder",
               let path = item.plainText, FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                pasteboard.writeObjects([url as NSURL])
            }

        case .fileURL:
            if let path = item.plainText {
                let url = URL(fileURLWithPath: path)
                pasteboard.writeObjects([url as NSURL])
            }

        case .webURL:
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
                if let url = URL(string: text) {
                    pasteboard.setString(url.absoluteString, forType: .URL)
                }
            }

        case .rtf:
            if let rich = item.richContent, let rtfData = rich.data(using: .utf8) {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            if let plain = item.plainText {
                pasteboard.setString(plain, forType: .string)
            }

        case .html:
            if let rich = item.richContent {
                pasteboard.setString(rich, forType: .html)
            }
            if let plain = item.plainText {
                pasteboard.setString(plain, forType: .string)
            }

        case .text:
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
            }
        }

        ClipboardMonitor.shared.markExpectedInternalChangeCount(pasteboard.changeCount)

        // 2. Dismiss panel callback immediately
        onComplete?()

        // 3. Deactivate self and restore original frontmost application
        NSApp.deactivate()

        var appToActivate = targetApp
        if appToActivate == nil || appToActivate?.bundleIdentifier == Bundle.main.bundleIdentifier {
            appToActivate = NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !$0.isTerminated
            })
        }

        if let target = appToActivate {
            target.activate()
        }

        // 4. Simulate Cmd + V after focus settle delay (100ms ensures target window is active)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            if AXIsProcessTrusted() {
                self.dispatchSyntheticPaste()
            } else {
                NSLog("Accessibility permissions not granted. Content copied to clipboard for manual paste.")
            }
        }
    }

    private func dispatchSyntheticPaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKeyCode: CGKeyCode = 0x09 // ANSI 'V'

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = []

        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15)) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    public static var isAccessibilityTrusted: Bool {
        return AXIsProcessTrusted()
    }

    public static func promptForAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    public static var isFullDiskAccessGranted: Bool {
        let testPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Safari")
        return FileManager.default.isReadableFile(atPath: testPath)
    }

    public static func promptForFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
