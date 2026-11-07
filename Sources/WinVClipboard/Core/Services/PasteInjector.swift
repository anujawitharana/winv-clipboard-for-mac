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

        switch item.contentType {
        case .image:
            if let relPath = item.imageRelativePath, let imgData = store.fullImageData(for: relPath) {
                pasteboard.setData(imgData, forType: .png)
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

        // 2. Dismiss panel callback
        onComplete?()

        // 3. Deactivate self and restore original frontmost application
        NSApp.deactivate()
        if let target = targetApp {
            target.activate()
        }

        // 4. Simulate Cmd + V after focus settle delay (120ms ensures OS routes focus to target window)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
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
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
