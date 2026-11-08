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
    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    public override var acceptsFirstResponder: Bool {
        return false
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
