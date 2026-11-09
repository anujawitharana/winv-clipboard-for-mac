import Foundation
import AppKit

public struct GitHubAsset: Codable, Equatable {
    public let name: String
    public let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }

    public init(name: String, browserDownloadURL: String) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
    }
}

public struct GitHubRelease: Codable, Equatable {
    public let id: Int
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }

    public init(id: Int, tagName: String, name: String?, body: String?, htmlURL: String, assets: [GitHubAsset]) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.assets = assets
    }
}

public struct ReleaseInfo: Equatable, Identifiable {
    public let id: Int
    public let tagName: String
    public let version: String
    public let title: String
    public let changelog: String
    public let releaseURL: URL
    public let downloadURL: URL?
    public let assetName: String?

    public init(id: Int, tagName: String, version: String, title: String, changelog: String, releaseURL: URL, downloadURL: URL?, assetName: String?) {
        self.id = id
        self.tagName = tagName
        self.version = version
        self.title = title
        self.changelog = changelog
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.assetName = assetName
    }
}

public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(ReleaseInfo)
    case downloading(progress: Double)
    case extracting
    case readyToRestart(executablePath: String)
    case error(String)
}

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public private(set) var status: UpdateStatus = .idle
    @Published public private(set) var lastCheckedDate: Date? {
        didSet {
            if let date = lastCheckedDate {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "WinVLastUpdateCheck")
            }
        }
    }

    public var isAutoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "WinVAutoCheckUpdates") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "WinVAutoCheckUpdates")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "WinVAutoCheckUpdates")
            objectWillChange.send()
        }
    }

    public var availableRelease: ReleaseInfo? {
        if case .updateAvailable(let info) = status {
            return info
        }
        return nil
    }

    public let currentVersion: String

    public var repoOwner: String = "anujawitharana"
    public var repoName: String = "clipbaord-for-mac"

    public init(currentVersion: String? = nil) {
        if let ver = currentVersion {
            self.currentVersion = ver
        } else {
            self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        }

        let savedTime = UserDefaults.standard.double(forKey: "WinVLastUpdateCheck")
        if savedTime > 0 {
            self.lastCheckedDate = Date(timeIntervalSince1970: savedTime)
        }
    }

    nonisolated public static func isVersion(_ newVersion: String, newerThan currentVersion: String) -> Bool {
        let cleanNew = newVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let cleanCurrent = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

        let newComponents = cleanNew.split(separator: ".").compactMap { Int($0) }
        let currentComponents = cleanCurrent.split(separator: ".").compactMap { Int($0) }

        let count = max(newComponents.count, currentComponents.count)
        for i in 0..<count {
            let n = i < newComponents.count ? newComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }

    public func checkForUpdates(isUserInitiated: Bool = true) async {
        if !isUserInitiated {
            if let last = lastCheckedDate, Date().timeIntervalSince(last) < 86400 {
                return
            }
            guard isAutoCheckEnabled else { return }
        }

        status = .checking

        guard let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            status = .error("Invalid update URL configuration.")
            return
        }

        var request = URLRequest(url: apiURL)
        request.setValue("WinVClipboard/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                status = .error("Invalid server response.")
                return
            }

            if httpResponse.statusCode == 404 {
                // No releases published on GitHub yet
                self.lastCheckedDate = Date()
                status = .upToDate(version: currentVersion)
                return
            }

            guard httpResponse.statusCode == 200 else {
                status = .error("GitHub returned HTTP status \(httpResponse.statusCode).")
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

            self.lastCheckedDate = Date()

            if Self.isVersion(latestVersion, newerThan: currentVersion) {
                // Find matching zip asset
                let zipAsset = release.assets.first(where: {
                    $0.name.hasSuffix(".zip") || $0.name.localizedCaseInsensitiveContains("winvclipboard")
                }) ?? release.assets.first

                let downloadURL = zipAsset.flatMap { URL(string: $0.browserDownloadURL) }
                let releasePageURL = URL(string: release.htmlURL) ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!

                let info = ReleaseInfo(
                    id: release.id,
                    tagName: release.tagName,
                    version: latestVersion,
                    title: release.name ?? "Release \(release.tagName)",
                    changelog: release.body ?? "No release notes provided.",
                    releaseURL: releasePageURL,
                    downloadURL: downloadURL,
                    assetName: zipAsset?.name
                )

                status = .updateAvailable(info)
            } else {
                status = .upToDate(version: currentVersion)
            }
        } catch {
            if isUserInitiated {
                status = .error(error.localizedDescription)
            } else {
                status = .idle
            }
        }
    }

    public func downloadAndInstall(release: ReleaseInfo) async {
        guard let downloadURL = release.downloadURL else {
            NSWorkspace.shared.open(release.releaseURL)
            return
        }

        status = .downloading(progress: 0.1)

        do {
            let (tempLocalURL, _) = try await URLSession.shared.download(from: downloadURL)
            status = .downloading(progress: 0.9)

            status = .extracting

            let fileManager = FileManager.default
            let stagingDirectory = fileManager.temporaryDirectory.appendingPathComponent("WinVUpdate_\(UUID().uuidString)")
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

            // Extract with ditto
            let dittoProcess = Process()
            dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProcess.arguments = ["-x", "-k", tempLocalURL.path, stagingDirectory.path]
            try dittoProcess.run()
            dittoProcess.waitUntilExit()

            guard dittoProcess.terminationStatus == 0 else {
                throw NSError(domain: "WinVUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update package."])
            }

            // Find extracted .app
            let items = try fileManager.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil)
            guard let extractedApp = items.first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "WinVUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "No application bundle found inside update package."])
            }

            let destinationAppPath = Bundle.main.bundlePath
            guard destinationAppPath.hasSuffix(".app") else {
                // Development mode, open the extracted folder
                NSWorkspace.shared.activateFileViewerSelecting([extractedApp])
                status = .idle
                return
            }

            // Perform in-place relaunch script
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let script = """
            while kill -0 \(currentPID) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(destinationAppPath)"
            cp -R "\(extractedApp.path)" "\(destinationAppPath)"
            xattr -cr "\(destinationAppPath)"
            open "\(destinationAppPath)"
            rm -rf "\(stagingDirectory.path)"
            """

            let helperProcess = Process()
            helperProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
            helperProcess.arguments = ["-c", script]
            try helperProcess.run()

            status = .readyToRestart(executablePath: destinationAppPath)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    public func resetStatus() {
        status = .idle
    }
}
