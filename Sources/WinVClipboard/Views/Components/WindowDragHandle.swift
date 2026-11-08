import SwiftUI
import AppKit

public struct WindowDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> WindowDragView {
        return WindowDragView()
    }

    public func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

public final class WindowDragView: NSView {
    private var isDragging = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero

    public override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        isDragging = true
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window.frame.origin
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window else { return }
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - dragStartMouse.x
        let deltaY = currentMouse.y - dragStartMouse.y
        window.setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + deltaX,
            y: dragStartOrigin.y + deltaY
        ))
    }

    public override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    public override var acceptsFirstResponder: Bool {
        return false
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
