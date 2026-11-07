# WinV Clipboard for macOS

**WinV Clipboard** is a native macOS clipboard manager that brings the fluid ergonomics and design of the **Windows 11 Clipboard History (`Win + V`)** directly to macOS.

Built with **Swift 5.10+**, **AppKit**, and **SwiftUI**, it runs as an ultra-lightweight menu-bar agent (`LSUIElement = true`) featuring a floating acrylic panel, caret-anchored positioning, instant auto-paste, and local privacy protection.

---

## Key Features

- **Windows 11 Fluent Acrylic Flyout**: Translucent `.ultraThinMaterial` floating card panel with rounded corners, subtle border, and native dark/light appearance.
- **Smart Caret & Cursor Positioning**: Appears directly below the active text caret via Accessibility API; automatically falls back to the mouse cursor or screen center if caret inspection is unavailable.
- **Direct Auto-Paste**: Selecting a clip or pressing `Enter` restores focus to the active target application and immediately simulates `⌘V` (Command + V).
- **Configurable Global Shortcut**: Defaults to **`⌥V` (Option + V)**, matching the tactile feel of `Win + V` on a Mac keyboard. An interactive shortcut recorder in Settings allows you to configure any combination (e.g. `⌘⇧V`, `⌃⌥V`) with conflict detection.
- **SQLite + Local Disk Storage**: Persistent history stored locally in `~/Library/Application Support/WinVClipboard/clipboard.db` (SQLite in WAL mode). Images and downsampled thumbnails are managed on the filesystem.
- **Pinning & Pruning**: Pin important clips so they survive history limits and "Clear all". Unpinned clips are automatically pruned beyond your configured limit (default: 50 clips).
- **Rich Media & Content Support**: Plain text, Rich Text (RTF), HTML snippets, Web URLs, File URLs, and PNG/TIFF images with instant preview thumbnails.
- **Content Deduplication & Self-Suppression**: SHA-256 content hashing deduplicates repeated copies and brings existing items back to the top. Internal restoration operations are suppressed so pasting doesn't create duplicate history items.
- **Privacy & Password Manager Protection**:
  - Automatically detects concealed markers: `org.nspasteboard.ConcealedType`, `com.agilebits.onepassword`, `org.nspasteboard.TransientType`, `PasswordPboardType`.
  - Built-in blacklisting of known password managers: 1Password, Bitwarden, Apple Keychain, KeePassXC, LastPass, Dashlane, Enpass, NordPass.
  - Custom app exclusion blacklist table in Settings.
  - One-click "Pause Monitoring" toggle.
  - Zero telemetry or network transmission: 100% of data remains offline on your Mac.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌥V`** (Option + V) | Open or dismiss the clipboard flyout (customizable in Settings) |
| **`↑` / `↓`** | Navigate through clipboard items |
| **`↵`** (Enter / Return) | Paste selected item into the frontmost application |
| **`⌫`** (Delete / Backspace) | Delete the selected clipboard item |
| **`⌘F`** | Focus the search input field |
| **`⎋`** (Escape) | Dismiss the clipboard flyout |

---

## Architecture Overview

```
WinVClipboard/
├── Package.swift                    # Swift Package Manager configuration
├── Resources/
│   └── Info.plist                   # App bundle metadata (LSUIElement = 1)
├── Scripts/
│   └── build_app.sh                 # Release compilation & bundle script
├── Sources/
│   └── WinVClipboard/
│       ├── main.swift               # Application entry point
│       ├── App/
│       │   ├── AppDelegate.swift    # App coordination & lifecycle
│       │   └── StatusItemManager.swift # Menu bar tray icon & menu
│       ├── Core/
│       │   ├── Models/
│       │   │   ├── ClipboardItem.swift # Data model with metadata & hashing
│       │   │   ├── ContentType.swift   # Text, RTF, HTML, Image, File, URL
│       │   │   └── KeyCombo.swift      # Carbon hotkey model & conflict detection
│       │   ├── Storage/
│       │   │   ├── DatabaseManager.swift # SQLite3 wrapper with WAL & transactions
│       │   │   ├── FileStorageManager.swift # Binary image store & thumbnail generator
│       │   │   └── ClipboardStore.swift # Primary data repository coordinator
│       │   └── Services/
│       │       ├── ClipboardMonitor.swift # Background NSPasteboard changeCount poller
│       │       ├── PrivacyFilter.swift    # Concealed types & app exclusion engine
│       │       ├── HotkeyManager.swift    # Carbon RegisterEventHotKey engine
│       │       ├── CaretLocator.swift     # 3-tier positioning (AX Caret → Mouse → Center)
│       │       ├── PasteInjector.swift    # CGEvent synthetic Cmd+V injector
│       │       └── LaunchAtLoginService.swift # SMAppService login item manager
│       ├── Window/
│       │   ├── ClipboardPanel.swift   # Custom floating, acrylic NSPanel
│       │   ├── PanelController.swift  # Window presenter & focus coordinator
│       │   └── SettingsWindowController.swift # Preferences window coordinator
│       └── Views/
│           ├── Flyout/
│           │   ├── ClipboardFlyoutView.swift # Windows 11 flyout interface
│           │   ├── FlyoutHeaderView.swift    # Search bar & actions
│           │   ├── ClipboardCardView.swift   # Individual clipboard card
│           │   └── EmptyHistoryView.swift    # Empty state view
│           ├── Settings/
│           │   ├── SettingsView.swift        # Preferences tabs
│           │   ├── ShortcutRecorderView.swift # Key recorder view
│           │   └── ExclusionListView.swift   # Excluded apps manager
│           └── Components/
│               └── AcrylicBackground.swift   # NSVisualEffectView wrapper
└── Tests/
    └── WinVClipboardTests/          # Unit & integration test suite
```

---

## Build & Run Instructions

### Prerequisites
- macOS 14.0 or newer
- Xcode 15+ or Swift 5.10+ command-line tools

### Building the `.app` Bundle
Run the packaging script from the project root:

```bash
./Scripts/build_app.sh
```

This compiles a release binary and generates a signed standalone app bundle: `WinVClipboard.app`.

### Launching the Application
Double-click `WinVClipboard.app` in Finder, or launch it from Terminal:

```bash
open WinVClipboard.app
```

The app will appear in your top macOS menu bar as a clipboard icon.

### Running Tests
To run the automated test suite:

```bash
swift test
```

---

## Accessibility Permissions for Direct Auto-Paste

When you click an item or press `Enter`, WinV Clipboard restores your previously active application and synthesizes `⌘V` using `CGEvent`.

To enable this:
1. Open **System Settings** $\to$ **Privacy & Security** $\to$ **Accessibility**.
2. Enable **WinV Clipboard**.
3. (Optional) You can also click the status indicator in **Preferences $\to$ Permissions** or the menu bar item to trigger the system prompt directly.

*Note: If Accessibility permissions are not yet granted, selecting an item copies it to your clipboard with a reminder to grant permission, allowing manual `⌘V` paste.*

---

## Storage Location

All application data is maintained locally under:
```
~/Library/Application Support/WinVClipboard/
├── clipboard.db          # SQLite database with metadata & text
├── images/               # Full-resolution cached images
└── thumbnails/           # Downsampled fast-loading thumbnail cache
```
