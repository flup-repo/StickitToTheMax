import AppKit
import Foundation

public struct SemanticVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        // Strip any pre-release or build metadata suffix (e.g. "-beta.1" or "+123")
        let core = cleaned.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? cleaned
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        self.major = parts[0]
        self.minor = parts.count > 1 ? parts[1] : 0
        self.patch = parts.count > 2 ? parts[2] : 0
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

public struct GitHubRelease: Codable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let htmlURL: URL?
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    public var version: SemanticVersion? {
        SemanticVersion(string: tagName)
    }

    public var dmgAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case downloading(version: String)
    case installing(version: String)
}

protocol UpdateManagerDelegate: AnyObject {
    func updateManagerDidChangeStatus(_ status: UpdateStatus)
    func updateManagerWillRelaunchForUpdate()
}

/// Checks GitHub Releases for newer `.dmg` installers and performs automatic download,
/// atomic app-bundle replacement, and relaunch with zero third-party dependencies.
final class UpdateManager {
    static let defaultRepository = "flup-repo/StickitToTheMax"
    private static let autoCheckDefaultsKey = "autoCheckForUpdates"
    private static let autoCheckInterval: TimeInterval = 6 * 60 * 60 // 6 hours

    weak var delegate: UpdateManagerDelegate?

    let repository: String
    private let userDefaults: UserDefaults
    private var autoCheckTimer: Timer?

    private(set) var status: UpdateStatus = .idle {
        didSet {
            guard status != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.updateManagerDidChangeStatus(self.status)
            }
        }
    }

    var isBusy: Bool {
        status != .idle
    }

    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var currentVersion: SemanticVersion {
        SemanticVersion(string: currentVersionString) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    var isAutoCheckEnabled: Bool {
        get { userDefaults.bool(forKey: Self.autoCheckDefaultsKey) }
        set {
            userDefaults.set(newValue, forKey: Self.autoCheckDefaultsKey)
            syncAutoCheckSchedule()
        }
    }

    init(repository: String = UpdateManager.defaultRepository, userDefaults: UserDefaults = .standard) {
        self.repository = repository
        self.userDefaults = userDefaults
    }

    deinit {
        autoCheckTimer?.invalidate()
    }

    func startIfAutoCheckEnabled() {
        syncAutoCheckSchedule()
        if isAutoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self, self.isAutoCheckEnabled else { return }
                self.checkForUpdates(userInitiated: false)
            }
        }
    }

    func syncAutoCheckSchedule() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
        guard isAutoCheckEnabled else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.autoCheckInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates(userInitiated: false)
        }
        timer.tolerance = 600
        autoCheckTimer = timer
    }

    /// Checks GitHub Releases for a newer version with a `.dmg` asset.
    /// If found, automatically downloads, installs, and relaunches the updated app.
    func checkForUpdates(userInitiated: Bool) {
        guard !isBusy else { return }
        guard let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return
        }

        status = .checking

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("StickitToTheMax/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Update Check Failed",
                        message: "Could not reach GitHub to check for updates.\n\n\(error.localizedDescription)",
                        style: .warning
                    )
                }
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Update Check Failed",
                        message: "GitHub returned HTTP \(http.statusCode) while checking for updates.",
                        style: .warning
                    )
                }
                return
            }

            guard let data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Update Check Failed",
                        message: "Could not parse the latest release metadata from GitHub.",
                        style: .warning
                    )
                }
                return
            }

            guard !release.draft, !release.prerelease,
                  let remoteVersion = release.version,
                  let dmgAsset = release.dmgAsset else {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "You're Up to Date",
                        message: "StickitToTheMax v\(self.currentVersion) is the latest available release.",
                        style: .informational
                    )
                }
                return
            }

            guard remoteVersion > self.currentVersion else {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "You're Up to Date",
                        message: "StickitToTheMax v\(self.currentVersion) is already the latest version.",
                        style: .informational
                    )
                }
                return
            }

            self.downloadAndInstall(release: release, version: remoteVersion, asset: dmgAsset, userInitiated: userInitiated)
        }.resume()
    }

    // MARK: - Download & Install

    private func downloadAndInstall(
        release: GitHubRelease,
        version: SemanticVersion,
        asset: GitHubReleaseAsset,
        userInitiated: Bool
    ) {
        let targetAppURL = Bundle.main.bundleURL
        guard targetAppURL.pathExtension == "app" else {
            status = .idle
            if userInitiated {
                presentAlert(
                    title: "Update v\(version) Available",
                    message: "Automatic installation requires running StickitToTheMax.app. Download the DMG manually from GitHub Releases.",
                    style: .informational,
                    openURL: release.htmlURL
                )
            }
            return
        }

        let parentDir = targetAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDir.path) else {
            status = .idle
            if userInitiated {
                presentAlert(
                    title: "Cannot Replace App Automatically",
                    message: "StickitToTheMax does not have write permission to \(parentDir.path). Please download v\(version) from GitHub Releases.",
                    style: .warning,
                    openURL: release.htmlURL
                )
            }
            return
        }

        status = .downloading(version: version.description)

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("StickitToTheMax/\(currentVersionString)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        URLSession.shared.downloadTask(with: request) { [weak self] tempFileURL, response, error in
            guard let self else { return }

            if let error {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Download Failed",
                        message: "Could not download StickitToTheMax v\(version).\n\n\(error.localizedDescription)",
                        style: .warning,
                        openURL: release.htmlURL
                    )
                }
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Download Failed",
                        message: "GitHub returned HTTP \(http.statusCode) while downloading \(asset.name).",
                        style: .warning,
                        openURL: release.htmlURL
                    )
                }
                return
            }

            guard let tempFileURL else {
                self.status = .idle
                return
            }

            self.status = .installing(version: version.description)
            do {
                try self.stageAndRelaunch(dmgTempURL: tempFileURL, targetAppURL: targetAppURL)
            } catch {
                self.status = .idle
                if userInitiated {
                    self.presentAlert(
                        title: "Update Install Failed",
                        message: "Downloaded v\(version), but installation failed:\n\n\(error.localizedDescription)",
                        style: .warning,
                        openURL: release.htmlURL
                    )
                }
            }
        }.resume()
    }

    private func stageAndRelaunch(dmgTempURL: URL, targetAppURL: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("StickitToTheMax-Update-\(UUID().uuidString)", isDirectory: true)
        let dmgURL = workDir.appendingPathComponent("update.dmg")
        let mountDir = workDir.appendingPathComponent("mount", isDirectory: true)
        let stagedAppURL = workDir.appendingPathComponent("StickitToTheMax.app", isDirectory: true)

        try fm.createDirectory(at: mountDir, withIntermediateDirectories: true)
        try fm.copyItem(at: dmgTempURL, to: dmgURL)

        // Mount DMG silently without opening Finder
        try runProcess("/usr/bin/hdiutil", arguments: [
            "attach", "-nobrowse", "-readonly", "-mountpoint", mountDir.path, dmgURL.path,
        ])
        defer {
            _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountDir.path, "-force"])
        }

        // Locate .app bundle inside mounted DMG
        let mountedItems = try fm.contentsOfDirectory(at: mountDir, includingPropertiesForKeys: nil)
        guard let sourceAppURL = mountedItems.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(
                domain: "StickitToTheMax.Updater",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No .app bundle found inside the downloaded DMG."]
            )
        }

        // Copy staged app out of the mounted volume before detaching
        try runProcess("/usr/bin/ditto", arguments: [sourceAppURL.path, stagedAppURL.path])

        let executableURL = stagedAppURL.appendingPathComponent("Contents/MacOS/StickitToTheMax")
        guard fm.isExecutableFile(atPath: executableURL.path) else {
            throw NSError(
                domain: "StickitToTheMax.Updater",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The downloaded app bundle appears incomplete."]
            )
        }

        // Flush state and hand off atomic replacement + relaunch to a detached shell process
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        TARGET="$2"
        STAGED="$3"
        WORKDIR="$4"
        BACKUP="${TARGET}.update-backup"
        rm -rf "$BACKUP"
        if mv "$TARGET" "$BACKUP"; then
            if /usr/bin/ditto "$STAGED" "$TARGET"; then
                rm -rf "$BACKUP"
            else
                rm -rf "$TARGET"
                mv "$BACKUP" "$TARGET"
                rm -rf "$WORKDIR"
                exit 1
            fi
        else
            rm -rf "$WORKDIR"
            exit 1
        fi
        /usr/bin/xattr -cr "$TARGET" 2>/dev/null || true
        /usr/bin/open "$TARGET"
        rm -rf "$WORKDIR"
        """

        DispatchQueue.main.async { [weak self] in
            self?.delegate?.updateManagerWillRelaunchForUpdate()

            let handoff = Process()
            handoff.executableURL = URL(fileURLWithPath: "/bin/sh")
            handoff.arguments = ["-c", script, "updater", "\(pid)", targetAppURL.path, stagedAppURL.path, workDir.path]
            do {
                try handoff.run()
                NSApp.terminate(nil)
            } catch {
                self?.status = .idle
                try? fm.removeItem(at: workDir)
                self?.presentAlert(
                    title: "Update Install Failed",
                    message: "Could not launch the update installer: \(error.localizedDescription)",
                    style: .warning
                )
            }
        }
    }

    private func runProcess(_ launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Exit code \(process.terminationStatus)"
            throw NSError(
                domain: "StickitToTheMax.Updater",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errText]
            )
        }
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style, openURL: URL? = nil) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            if openURL != nil {
                alert.addButton(withTitle: "Open Releases")
                alert.addButton(withTitle: "OK")
            } else {
                alert.addButton(withTitle: "OK")
            }
            if alert.runModal() == .alertFirstButtonReturn, let openURL {
                NSWorkspace.shared.open(openURL)
            }
        }
    }
}
