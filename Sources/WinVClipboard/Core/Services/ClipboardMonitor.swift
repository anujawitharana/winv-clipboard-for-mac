import Foundation
import AppKit
import CommonCrypto

public final class ClipboardMonitor: @unchecked Sendable {
    public static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.winvclipboard.monitor", qos: .utility)
    private let lock = NSLock()

    // Internal restoration lock to prevent recording our own paste restoration
    private var _isInternalRestoration: Bool = false
    public var isInternalRestoration: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isInternalRestoration
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isInternalRestoration = newValue
        }
    }

    public var pollingIntervalMs: Int = 250 {
        didSet {
            restartTimer()
        }
    }

    public init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        restartTimer()
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
        }
    }

    private func restartTimer() {
        queue.sync {
            timer?.cancel()
            let source = DispatchSource.makeTimerSource(queue: queue)
            let interval = DispatchTimeInterval.milliseconds(pollingIntervalMs)
            source.schedule(deadline: .now() + interval, repeating: interval)
            source.setEventHandler { [weak self] in
                self?.checkPasteboard()
            }
            source.resume()
            self.timer = source
        }
    }

    private func checkPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // If this change was initiated by our own auto-paste restoration, skip it
        if isInternalRestoration {
            isInternalRestoration = false
            return
        }

        // Get frontmost application info
        let frontApp = NSWorkspace.shared.frontmostApplication
        let sourceAppName = frontApp?.localizedName
        let sourceBundleID = frontApp?.bundleIdentifier

        // Check privacy filter
        if PrivacyFilter.shared.shouldIgnore(pasteboard: pasteboard, sourceBundleID: sourceBundleID) {
            return
        }

        // Process types
        processPasteboardData(sourceAppName: sourceAppName, sourceBundleID: sourceBundleID)
    }

    private func processPasteboardData(sourceAppName: String?, sourceBundleID: String?) {
        guard let types = pasteboard.types, !types.isEmpty else { return }

        // 1. Check for Direct Image content (PNG, TIFF, JPEG, HEIC, GIF, or NSImage)
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.image")
        ]

        var capturedImageData: Data?
        for imgType in imageTypes {
            if types.contains(imgType), let data = pasteboard.data(forType: imgType), !data.isEmpty {
                if data.count <= 30 * 1024 * 1024 {
                    if imgType == .tiff, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
                        capturedImageData = png
                    } else {
                        capturedImageData = data
                    }
                    break
                }
            }
        }

        // Also check if NSImage can read objects directly (e.g. from browsers, screenshots, Preview)
        if capturedImageData == nil,
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let firstImage = images.first,
           let tiff = firstImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            capturedImageData = png
        }

        if let finalData = capturedImageData {
            let hash = sha256(data: finalData)
            Task { @MainActor in
                let maxCount = UserDefaults.standard.integer(forKey: "WinVMaxHistory")
                ClipboardStore.shared.addOrUpdateItem(
                    contentType: .image,
                    plainText: nil,
                    richContent: nil,
                    imageData: finalData,
                    sourceAppName: sourceAppName,
                    sourceAppBundleId: sourceBundleID,
                    contentHash: hash,
                    maxHistoryCount: maxCount > 0 ? maxCount : 50
                )
            }
            return
        }

        // 2. Check for File URLs
        if types.contains(.fileURL), let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstURL = urls.first {
            let path = firstURL.path
            let ext = firstURL.pathExtension.lowercased()
            let imageExtensions: Set<String> = [
                "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "svg", "ico", "icns", "avif"
            ]

            // If it's an image file, load image data and save as .image with thumbnail preview!
            if imageExtensions.contains(ext), let imgData = try? Data(contentsOf: firstURL), !imgData.isEmpty, imgData.count <= 30 * 1024 * 1024 {
                let hash = sha256(data: imgData)
                Task { @MainActor in
                    let maxCount = UserDefaults.standard.integer(forKey: "WinVMaxHistory")
                    ClipboardStore.shared.addOrUpdateItem(
                        contentType: .image,
                        plainText: path,
                        richContent: nil,
                        imageData: imgData,
                        sourceAppName: sourceAppName,
                        sourceAppBundleId: sourceBundleID,
                        contentHash: hash,
                        maxHistoryCount: maxCount > 0 ? maxCount : 50
                    )
                }
                return
            }

            // Normal non-image file
            let hash = sha256(string: "file:" + path)
            Task { @MainActor in
                let maxCount = UserDefaults.standard.integer(forKey: "WinVMaxHistory")
                ClipboardStore.shared.addOrUpdateItem(
                    contentType: .fileURL,
                    plainText: path,
                    richContent: nil,
                    imageData: nil,
                    sourceAppName: sourceAppName,
                    sourceAppBundleId: sourceBundleID,
                    contentHash: hash,
                    maxHistoryCount: maxCount > 0 ? maxCount : 50
                )
            }
            return
        }

        // 3. Check for Web URL
        if types.contains(.URL), let urlString = pasteboard.string(forType: .URL), let url = URL(string: urlString), url.scheme != nil {
            let hash = sha256(string: "url:" + urlString)
            Task { @MainActor in
                let maxCount = UserDefaults.standard.integer(forKey: "WinVMaxHistory")
                ClipboardStore.shared.addOrUpdateItem(
                    contentType: .webURL,
                    plainText: urlString,
                    richContent: nil,
                    imageData: nil,
                    sourceAppName: sourceAppName,
                    sourceAppBundleId: sourceBundleID,
                    contentHash: hash,
                    maxHistoryCount: maxCount > 0 ? maxCount : 50
                )
            }
            return
        }

        // 4. Check for Rich Text / HTML
        var richSnippet: String? = nil
        var isRich = false
        if types.contains(.rtf), let rtfData = pasteboard.data(forType: .rtf) {
            richSnippet = String(data: rtfData, encoding: .utf8) ?? rtfData.base64EncodedString()
            isRich = true
        } else if types.contains(.html), let htmlStr = pasteboard.string(forType: .html) {
            richSnippet = htmlStr
            isRich = true
        }

        // 5. Plain text
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Guard against massive text freeze (cap at 500k characters)
            let safeString = String(string.prefix(500_000))
            let hash = sha256(string: safeString)

            let contentType: ContentType
            if isRich {
                contentType = .rtf
            } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                contentType = .webURL
            } else {
                contentType = .text
            }

            Task { @MainActor in
                let maxCount = UserDefaults.standard.integer(forKey: "WinVMaxHistory")
                ClipboardStore.shared.addOrUpdateItem(
                    contentType: contentType,
                    plainText: safeString,
                    richContent: richSnippet,
                    imageData: nil,
                    sourceAppName: sourceAppName,
                    sourceAppBundleId: sourceBundleID,
                    contentHash: hash,
                    maxHistoryCount: maxCount > 0 ? maxCount : 50
                )
            }
        }
    }

    private func sha256(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(string: String) -> String {
        return sha256(data: Data(string.utf8))
    }
}
