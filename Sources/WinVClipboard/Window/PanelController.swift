import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    public static let focusClipboardSearch = Notification.Name("com.winvclipboard.focusSearch")
}

@MainActor
public final class PanelController: ObservableObject {
    public static let shared = PanelController()

    private var panel: ClipboardPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    public private(set) var previouslyActiveApp: NSRunningApplication?

    public let panelSize = CGSize(width: 380, height: 520)

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let contentRect = NSRect(origin: .zero, size: panelSize)
        let panel = ClipboardPanel(contentRect: contentRect)
        self.panel = panel

        let flyoutView = ClipboardFlyoutView(
            onItemChosen: { [weak self] item in
                self?.pasteItem(item)
            },
            onCloseRequested: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: flyoutView)
        hostingView.frame = contentRect
        panel.contentView = hostingView

        panel.onEscapePressed = { [weak self] in
            self?.hide()
        }

        panel.onDownArrowPressed = {
            ClipboardStore.shared.selectNext()
        }

        panel.onUpArrowPressed = {
            ClipboardStore.shared.selectPrevious()
        }

        panel.onEnterPressed = { [weak self] in
            if let item = ClipboardStore.shared.selectedItem {
                self?.pasteItem(item)
            }
        }

        panel.onDeletePressed = {
            if let item = ClipboardStore.shared.selectedItem {
                ClipboardStore.shared.deleteItem(item)
            }
        }

        panel.onSearchShortcutPressed = {
            NotificationCenter.default.post(name: .focusClipboardSearch, object: nil)
        }
    }

    public var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func show() {
        guard let panel = panel else { return }

        // Capture previous frontmost app
        let currentFront = NSWorkspace.shared.frontmostApplication
        if currentFront?.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previouslyActiveApp = currentFront
        }

        // Always reload latest items from database upon opening
        ClipboardStore.shared.refreshSync()

        // Calculate positioning
        let origin = CaretLocator.calculateFlyoutOrigin(panelSize: panelSize)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate()
        NSApp.activate()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1.0
        }

        installOutsideClickMonitors()
    }

    public func hide() {
        guard let panel = panel, panel.isVisible else { return }
        removeOutsideClickMonitors()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func pasteItem(_ item: ClipboardItem) {
        let targetApp = previouslyActiveApp
        PasteInjector.shared.pasteItem(item, targetApp: targetApp) { [weak self] in
            self?.hide()
        }
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        // Global monitor for clicks in other applications
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLoc) {
                self.hide()
            }
        }

        // Local monitor for clicks outside the window bounds
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            let clickLocationInWindow = event.locationInWindow
            let bounds = panel.contentView?.bounds ?? .zero
            if !bounds.contains(clickLocationInWindow) {
                self.hide()
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
}
