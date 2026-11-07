import Foundation
import AppKit
import ApplicationServices

public struct CaretLocator {
    /// Calculates the optimal origin (bottom-left in AppKit coordinates) for the flyout panel.
    @MainActor
    public static func calculateFlyoutOrigin(panelSize: CGSize) -> CGPoint {
        // Find the active screen (where the mouse is or main screen)
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let targetScreen = screens.first(where: { NSPointInRect(mouseLocation, $0.frame) }) ?? NSScreen.main ?? screens[0]
        let screenFrame = targetScreen.visibleFrame

        // 1. Attempt Accessibility Caret Position
        if let caretOrigin = getAccessibilityCaretOrigin(panelSize: panelSize, screenFrame: screenFrame) {
            return caretOrigin
        }

        // 2. Fallback: Mouse Cursor Position
        let mouseBasedOrigin = getMouseBasedOrigin(mouseLocation: mouseLocation, panelSize: panelSize, screenFrame: screenFrame)
        return mouseBasedOrigin
    }

    private static func getAccessibilityCaretOrigin(panelSize: CGSize, screenFrame: CGRect) -> CGPoint? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementValue
        )

        guard focusedResult == .success, let focusedElement = focusedElementValue else {
            return nil
        }

        let axElement = focusedElement as! AXUIElement
        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )

        guard rangeResult == .success, let rangeVal = selectedRangeValue else {
            return nil
        }

        var boundsValue: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal,
            &boundsValue
        )

        guard boundsResult == .success, let axValue = boundsValue else {
            return nil
        }

        var caretRect = CGRect.zero
        guard AXValueGetValue(axValue as! AXValue, .cgRect, &caretRect) else {
            return nil
        }

        // Accessibility coordinates are top-left origin; convert to AppKit bottom-left
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let appKitCaretY = primaryScreenHeight - (caretRect.origin.y + caretRect.height)

        var x = caretRect.origin.x
        var y = appKitCaretY - panelSize.height - 8 // 8px below caret

        // Clamp to screen bounds
        if x + panelSize.width > screenFrame.maxX {
            x = screenFrame.maxX - panelSize.width - 12
        }
        if x < screenFrame.minX {
            x = screenFrame.minX + 12
        }
        if y < screenFrame.minY {
            // Flip above caret if no space below
            y = appKitCaretY + caretRect.height + 8
        }
        if y + panelSize.height > screenFrame.maxY {
            y = screenFrame.maxY - panelSize.height - 12
        }

        return CGPoint(x: x, y: y)
    }

    private static func getMouseBasedOrigin(mouseLocation: CGPoint, panelSize: CGSize, screenFrame: CGRect) -> CGPoint {
        var x = mouseLocation.x + 12
        var y = mouseLocation.y - panelSize.height - 12

        // Clamp inside screen bounds
        if x + panelSize.width > screenFrame.maxX {
            x = mouseLocation.x - panelSize.width - 12
        }
        if x < screenFrame.minX {
            x = screenFrame.minX + 12
        }
        if y < screenFrame.minY {
            y = mouseLocation.y + 12
        }
        if y + panelSize.height > screenFrame.maxY {
            y = screenFrame.maxY - panelSize.height - 12
        }

        return CGPoint(x: x, y: y)
    }
}
