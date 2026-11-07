import Foundation
import AppKit

public final class ClipboardPanel: NSPanel {
    public var onEscapePressed: (() -> Void)?
    public var onDownArrowPressed: (() -> Void)?
    public var onUpArrowPressed: (() -> Void)?
    public var onEnterPressed: (() -> Void)?
    public var onDeletePressed: (() -> Void)?
    public var onSearchShortcutPressed: (() -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return true
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let isEditingText: Bool
            if let responder = firstResponder as? NSTextView {
                isEditingText = responder.isFieldEditor
            } else {
                isEditingText = false
            }

            switch event.keyCode {
            case 53: // Escape
                onEscapePressed?()
                return

            case 125: // Down Arrow
                onDownArrowPressed?()
                return

            case 126: // Up Arrow
                onUpArrowPressed?()
                return

            case 36, 76: // Enter / Return
                onEnterPressed?()
                return

            case 51: // Backspace / Delete
                if !isEditingText {
                    onDeletePressed?()
                    return
                }

            default:
                if event.keyCode == 3 && event.modifierFlags.contains(.command) { // Cmd + F
                    onSearchShortcutPressed?()
                    return
                }
            }
        }
        super.sendEvent(event)
    }
}
