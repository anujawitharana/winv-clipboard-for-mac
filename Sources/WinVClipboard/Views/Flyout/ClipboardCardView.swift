import SwiftUI
import AppKit

public struct ClipboardCardView: View {
    public let item: ClipboardItem
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onTogglePin: () -> Void
    public let onDelete: () -> Void

    @State private var isHovered: Bool = false
    @State private var asyncImage: NSImage? = nil
    @ObservedObject private var store = ClipboardStore.shared

    private var previewImage: NSImage? {
        if let asyncImage = asyncImage {
            return asyncImage
        }
        if let thumbPath = item.thumbnailRelativePath, let cached = store.cachedThumbnail(for: thumbPath) {
            return cached
        }
        return nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Card Header: Content Type / App name + Actions
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: item.contentType.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)

                if let appName = item.sourceAppName, !appName.isEmpty {
                    Text(appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Timestamp
                Text(item.relativeTimeFormatted)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))

                // Pin Button
                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(item.isPinned ? .accentColor : .secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin item" : "Pin item")

                // Delete Button (visible on hover or if pinned/focused)
                if isHovered || isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete item")
                }
            }

            // Card Body
            cardBodyContent()

            // Card Footer for Code / Length metadata
            if item.contentType == .text && item.charCount > 0 {
                HStack {
                    Spacer()
                    Text("\(item.charCount) chars")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .task(id: item.id) {
            await loadCardImageAsync()
        }
    }

    @ViewBuilder
    private func cardBodyContent() -> some View {
        switch item.contentType {
        case .image:
            VStack(alignment: .leading, spacing: 4) {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text(item.displayTitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if let text = item.plainText, !text.isEmpty {
                    let filename = (text as NSString).lastPathComponent
                    Text(filename)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }

        case .fileURL:
            if let image = previewImage {
                VStack(alignment: .leading, spacing: 4) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 140)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                    if let filePath = item.plainText {
                        Text((filePath as NSString).lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let urlText = item.plainText {
                        Text(urlText)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                            .lineLimit(2)
                    }
                }
            }

        case .webURL:
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let urlText = item.plainText {
                    Text(urlText)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                        .lineLimit(2)
                }
            }

        default:
            // Text or Rich Text
            let text = item.plainText ?? ""
            Text(text)
                .font(isProbablyCode(text) ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadCardImageAsync() async {
        guard item.contentType == .image || item.contentType == .fileURL else { return }

        // If already cached in memory, set immediately
        if let thumbPath = item.thumbnailRelativePath, let cached = store.cachedThumbnail(for: thumbPath) {
            self.asyncImage = cached
            return
        }

        let currentItem = self.item
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let fm = FileStorageManager()
            if let thumbPath = currentItem.thumbnailRelativePath,
               let img = fm.loadThumbnailImage(for: thumbPath) {
                return img
            }
            if let imgPath = currentItem.imageRelativePath {
                let url = fm.fullURL(for: imgPath)
                if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                    return img
                }
            }
            if let path = currentItem.plainText,
               FileManager.default.fileExists(atPath: path),
               let directImage = NSImage(contentsOfFile: path) {
                Task {
                    await ClipboardStore.shared.repairImageFromDisk(itemId: currentItem.id, filePath: path)
                }
                return directImage
            }
            return nil
        }.value

        if let loaded = loaded {
            self.asyncImage = loaded
            if let thumbPath = currentItem.thumbnailRelativePath {
                _ = store.thumbnailImage(for: thumbPath)
            }
        }
    }

    private func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "svg", "ico", "icns", "avif"
        ]
        return imageExtensions.contains(ext)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        if isHovered {
            return Color(nsColor: .controlBackgroundColor).opacity(0.85)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(0.2)
        }
        return Color.primary.opacity(0.08)
    }

    private func isProbablyCode(_ string: String) -> Bool {
        let indicators = ["{", "}", "func ", "def ", "class ", "import ", "const ", "let ", "var ", ";\n", "public ", "private "]
        return indicators.contains { string.contains($0) }
    }
}
