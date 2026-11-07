import Foundation
import AppKit

public final class ClipboardPanel: NSPanel {
    public var onEscapePressed: (() -> Void)?

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    public override var canBecomeKey: Bool {
        return true
    }

    public override var canBecomeMain: Bool {
        return false
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}
