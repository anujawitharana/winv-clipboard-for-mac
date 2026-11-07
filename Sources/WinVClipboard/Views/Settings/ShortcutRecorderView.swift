import SwiftUI
import AppKit
import Carbon

public struct ShortcutRecorderView: View {
    @State private var isRecording: Bool = false
    @State private var activeCombo: KeyCombo = HotkeyManager.shared.activeShortcut
    @State private var conflictWarning: String?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button(action: {
                    isRecording.toggle()
                    conflictWarning = nil
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isRecording ? "record.circle.fill" : "command")
                            .foregroundColor(isRecording ? .red : .accentColor)

                        Text(isRecording ? "Press shortcut keys..." : activeCombo.displayString)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .frame(minWidth: 160)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.red.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.red : Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if activeCombo != KeyCombo.defaultShortcut {
                    Button("Reset to ⌥V") {
                        if HotkeyManager.shared.resetToDefault() {
                            activeCombo = HotkeyManager.shared.activeShortcut
                            conflictWarning = nil
                            isRecording = false
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
            .background(
                KeyRecorderRepresentable(
                    isRecording: $isRecording,
                    onKeyRecorded: { newCombo in
                        if newCombo.isSystemReservedConflict {
                            conflictWarning = "Conflicts with a standard macOS system shortcut."
                            return
                        }
                        if HotkeyManager.shared.updateShortcut(to: newCombo) {
                            activeCombo = newCombo
                            conflictWarning = nil
                            isRecording = false
                        } else {
                            conflictWarning = "Failed to register shortcut. Try another combination."
                        }
                    }
                )
            )

            if let warning = conflictWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }
}

private struct KeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyRecorded: (KeyCombo) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyRecorded = onKeyRecorded
        view.isRecordingBinding = { isRecording }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        nsView.isRecordingBinding = { isRecording }
    }
}

private final class KeyCaptureView: NSView {
    var onKeyRecorded: ((KeyCombo) -> Void)?
    var isRecordingBinding: (() -> Bool)?
    private var localMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, let isRecording = self.isRecordingBinding?(), isRecording else {
                    return event
                }

                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                // Must include at least one modifier key
                guard !modifiers.isEmpty else {
                    return event
                }

                // Disregard standalone modifier presses
                let carbonMods = KeyCombo.carbonModifiers(from: modifiers)
                let keyCode = UInt32(event.keyCode)

                let combo = KeyCombo(keyCode: keyCode, carbonModifiers: carbonMods)
                self.onKeyRecorded?(combo)
                return nil // Consume event
            }
        } else if window == nil, let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
