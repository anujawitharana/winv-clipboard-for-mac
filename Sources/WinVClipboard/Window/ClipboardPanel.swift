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

    private var isDraggingWindow: Bool = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero

    public override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let loc = event.locationInWindow
            // Header drag zone: top 56 points, excluding top-right action buttons (Clear all, Settings)
            if loc.y >= frame.height - 56 && loc.x < frame.width - 120 {
                isDraggingWindow = true
                dragStartMouse = NSEvent.mouseLocation
                dragStartOrigin = self.frame.origin
                return
            }

        case .leftMouseDragged:
            if isDraggingWindow {
                let currentMouse = NSEvent.mouseLocation
                let deltaX = currentMouse.x - dragStartMouse.x
                let deltaY = currentMouse.y - dragStartMouse.y
                self.setFrameOrigin(NSPoint(
                    x: dragStartOrigin.x + deltaX,
                    y: dragStartOrigin.y + deltaY
                ))
                return
            }

        case .leftMouseUp:
            if isDraggingWindow {
                isDraggingWindow = false
                return
            }

        default:
            break
        }

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
