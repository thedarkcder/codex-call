import AppKit
import AVFoundation
import Darwin

let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/CodexCall", isDirectory: true)

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var menuStateItem: NSMenuItem!
    var menuStartItem: NSMenuItem!
    var menuStopItem: NSMenuItem!
    var menuUpdateItem: NSMenuItem!

    let stateLabel = NSTextField(labelWithString: "Checking…")
    let detailLabel = NSTextField(labelWithString: "")
    let modeLabel = NSTextField(labelWithString: "")
    let installButton = NSButton(title: "Check for Updates…", target: nil, action: nil)
    let startButton = NSButton(title: "Start Routing", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop Routing", target: nil, action: nil)
    let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    var helperProcess: Process?
    var refreshTimer: Timer?
    var busy = false
    var userStopped = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenuBar()
        buildWindow()
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
            self?.ensureRouter()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.configureIfReady()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        stopRouter(silent: true)
    }

    func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: "Codex Call")
        statusMenu = NSMenu()
        menuStateItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
        menuStateItem.isEnabled = false
        statusMenu.addItem(menuStateItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Show Codex Call", action: #selector(showWindow), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        menuStartItem = NSMenuItem(title: "Start Routing", action: #selector(startRouterAction), keyEquivalent: "")
        menuStopItem = NSMenuItem(title: "Stop Routing", action: #selector(stopRouterAction), keyEquivalent: "")
        statusMenu.addItem(menuStartItem)
        statusMenu.addItem(menuStopItem)
        statusMenu.addItem(.separator())
        menuUpdateItem = NSMenuItem(title: "Check for Updates…", action: #selector(installAction), keyEquivalent: "")
        statusMenu.addItem(menuUpdateItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        for item in statusMenu.items { item.target = self }
        statusItem.menu = statusMenu
    }

    func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Call"
        window.center()
        window.isReleasedWhenClosed = false

        stateLabel.font = .boldSystemFont(ofSize: 18)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 0
        modeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        modeLabel.maximumNumberOfLines = 0

        installButton.target = self
        installButton.action = #selector(installAction)
        installButton.bezelStyle = .rounded
        startButton.target = self
        startButton.action = #selector(startRouterAction)
        startButton.bezelStyle = .rounded
        stopButton.target = self
        stopButton.action = #selector(stopRouterAction)
        stopButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quitAction)
        quitButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [installButton, startButton, stopButton, quitButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [stateLabel, detailLabel, modeLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
    }

    func setDisplayedStatus(_ state: String, detail: String) {
        stateLabel.stringValue = state
        detailLabel.stringValue = detail
        menuStateItem.title = state
        statusItem.button?.toolTip = state
    }

    func setUpdateAction(title: String, enabled: Bool) {
        installButton.title = title
        installButton.isEnabled = enabled
        menuUpdateItem.title = title
        menuUpdateItem.isEnabled = enabled
    }

    func syncMenuActions() {
        menuStartItem.isEnabled = startButton.isEnabled
        menuStopItem.isEnabled = stopButton.isEnabled
        menuUpdateItem.title = installButton.title
        menuUpdateItem.isEnabled = installButton.isEnabled
    }

    func helperPath() -> String {
        let installedAppHelper = "/usr/local/lib/codex-call/CodexCallHelper.app/Contents/MacOS/codex-call-helper"
        if FileManager.default.isExecutableFile(atPath: installedAppHelper) { return installedAppHelper }
        return bundledHelperPath() ?? "/usr/local/bin/codex-call-helper"
    }

    func bundledHelperPath() -> String? {
        if let app = Bundle.main.resourceURL?.appendingPathComponent(
            "CodexCallHelper.app/Contents/MacOS/codex-call-helper"
        ), FileManager.default.isExecutableFile(atPath: app.path) {
            return app.path
        }
        return Bundle.main.path(forResource: "codex-call-helper", ofType: nil)
    }

    @discardableResult
    func runHelper(_ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath())
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    func driverInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/CodexVirtualRX.driver")
            && fm.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/CodexVirtualTX.driver")
            && fm.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/CodexVirtualClock.driver")
    }

    func driverVersionsCurrent() -> Bool {
        ["CodexVirtualRX.driver", "CodexVirtualTX.driver", "CodexVirtualClock.driver"].allSatisfy { name in
            let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL").appendingPathComponent(name)
            return bundleInfoString(at: url, key: "CFBundleShortVersionString") == currentVersion()
        }
    }

    func bundleInfoString(at bundleURL: URL, key: String) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary[key] as? String
    }

    func componentsCurrent() -> Bool {
        driverInstalled() && driverVersionsCurrent() && !helperNeedsUpdate()
    }

    func configureIfReady() {
        removeLaunchAgent()
        guard componentsCurrent() else {
            refreshStatus()
            return
        }
        if !configurationExists() {
            runHelper(["setup"])
        }
        if let plugin = bundledPluginURL(), pluginNeedsUpdate(plugin: plugin) {
            installPlugin(plugin: plugin)
        }
        refreshStatus()
        if !isRouterRunning() { startRouter(silent: true) }
    }

    func configurationExists() -> Bool {
        FileManager.default.fileExists(atPath: appSupportDir.appendingPathComponent("config.json").path)
    }

    @objc func installAction() { checkForUpdates() }

    func checkForUpdates() {
        guard !busy else { return }
        busy = true
        setUpdateAction(title: "Checking…", enabled: false)
        startButton.isEnabled = false
        syncMenuActions()
        setDisplayedStatus("Checking for updates…", detail: "Looking for a signed Codex Call installer.")

        guard let endpoint = URL(string: bundleString("CodexCallReleaseAPIURL", fallback: "https://api.github.com/repos/thedarkcder/codex-call/releases/latest")) else {
            finishUpdateError("The update service URL is invalid.")
            return
        }
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CodexCall/\(currentVersion())", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.finishUpdateError("Could not check for updates: \(error.localizedDescription)") }
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                DispatchQueue.main.async { self.finishUpdateError("The update service returned an unexpected response.") }
                return
            }
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                DispatchQueue.main.async { self.handleRelease(release) }
            } catch {
                DispatchQueue.main.async { self.finishUpdateError("The update response could not be read: \(error.localizedDescription)") }
            }
        }.resume()
    }

    func helperNeedsUpdate() -> Bool {
        let installed = URL(fileURLWithPath: "/usr/local/lib/codex-call/CodexCallHelper.app")
        let identifier = bundleInfoString(at: installed, key: "CFBundleIdentifier")
        let version = bundleInfoString(at: installed, key: "CFBundleShortVersionString")
        return identifier != "com.codexcall.helper" || version != currentVersion()
    }

    func bundledPluginURL() -> URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("plugin")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    func pluginVersion(at root: URL) -> String? {
        let manifest = root.appendingPathComponent(".codex-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["version"] as? String
    }

    func pluginNeedsUpdate(plugin: URL) -> Bool {
        let installed = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("plugins/codex-call")
        return pluginVersion(at: plugin) != pluginVersion(at: installed)
    }

    func bundleString(_ key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }

    func currentVersion() -> String {
        bundleString("CFBundleShortVersionString", fallback: "0.0.0")
    }

    func releaseIsNewer(_ tag: String) -> Bool {
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        return latest.compare(currentVersion(), options: .numeric) == .orderedDescending
    }

    func handleRelease(_ release: GitHubRelease) {
        let needsInstaller = !componentsCurrent()
        guard needsInstaller || releaseIsNewer(release.tagName) else {
            finishUpdateUI()
            showAlert(title: "Codex Call is up to date", message: "Version \(currentVersion()) is the latest release.")
            return
        }
        guard let package = release.assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) else {
            finishUpdateUI()
            let alert = NSAlert()
            alert.messageText = "Installer package unavailable"
            alert.informativeText = "Release \(release.tagName) does not contain a macOS installer package."
            alert.addButton(withTitle: "Open Releases")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
            return
        }
        downloadInstaller(package, releaseTag: release.tagName)
    }

    func downloadInstaller(_ asset: GitHubRelease.Asset, releaseTag: String) {
        setDisplayedStatus("Downloading \(releaseTag)…", detail: "The installer signature will be verified before it opens.")
        URLSession.shared.downloadTask(with: asset.browserDownloadURL) { [weak self] temporaryURL, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.finishUpdateError("Could not download the installer: \(error.localizedDescription)") }
                return
            }
            guard let temporaryURL else {
                DispatchQueue.main.async { self.finishUpdateError("The installer download did not produce a file.") }
                return
            }
            do {
                let updates = appSupportDir.appendingPathComponent("Updates", isDirectory: true)
                try FileManager.default.createDirectory(at: updates, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: asset.name).lastPathComponent
                let destination = updates.appendingPathComponent(safeName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                let verification = self.verifyInstaller(at: destination)
                DispatchQueue.main.async {
                    guard verification.ok else {
                        try? FileManager.default.removeItem(at: destination)
                        self.finishUpdateError("The downloaded installer was rejected. \(verification.message)")
                        return
                    }
                    self.finishUpdateUI()
                    let alert = NSAlert()
                    alert.messageText = "Install \(releaseTag)?"
                    alert.informativeText = "The signed installer has been verified. Installer will request administrator approval; Codex Call itself never asks for or handles your password. The app will quit after Installer opens."
                    alert.addButton(withTitle: "Open Installer")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(destination)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                    }
                }
            } catch {
                DispatchQueue.main.async { self.finishUpdateError("Could not save the installer: \(error.localizedDescription)") }
            }
        }.resume()
    }

    func verifyInstaller(at url: URL) -> (ok: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--check-signature", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (false, "Signature verification could not start: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        let expectedTeam = bundleString("CodexCallExpectedTeamIdentifier", fallback: "9CGENKKT99")
        let trusted = process.terminationStatus == 0
            && output.contains("Developer ID Installer:")
            && output.contains("(\(expectedTeam))")
        return trusted ? (true, output) : (false, "It is not signed by the expected Developer ID Installer team \(expectedTeam).")
    }

    func finishUpdateUI() {
        busy = false
        setUpdateAction(
            title: componentsCurrent() ? "Check for Updates…" : "Install / Update…",
            enabled: true
        )
        refreshStatus()
    }

    func finishUpdateError(_ message: String) {
        finishUpdateUI()
        showAlert(title: "Update failed", message: message)
    }

    func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func removeLaunchAgent() {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.codexcall.router.plist")
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(getuid())/com.codexcall.router"]
        try? bootout.run()
        bootout.waitUntilExit()
        try? FileManager.default.removeItem(at: plist)
    }

    func installPlugin(plugin: URL) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dest = home.appendingPathComponent("plugins/codex-call")
        try? fm.createDirectory(at: home.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: plugin, to: dest)

        let marketplaceDir = home.appendingPathComponent(".agents/plugins")
        try? fm.createDirectory(at: marketplaceDir, withIntermediateDirectories: true)
        let marketplace = marketplaceDir.appendingPathComponent("marketplace.json")
        if !fm.fileExists(atPath: marketplace.path) {
            let json = """
            {
              "name": "personal",
              "interface": { "displayName": "Personal" },
              "plugins": [
                {
                  "name": "codex-call",
                  "source": { "source": "local", "path": "./plugins/codex-call" },
                  "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
                  "category": "Productivity"
                }
              ]
            }
            """
            try? json.write(to: marketplace, atomically: true, encoding: .utf8)
        }

        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
        guard let codex = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["plugin", "add", "codex-call@personal"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    func isRouterRunning() -> Bool {
        if let process = helperProcess, process.isRunning { return true }
        guard let pid = routerPID(), isCodexCallHelper(pid: pid) else { return false }
        return kill(pid, 0) == 0
    }

    func routerPID() -> Int32? {
        let pidFile = appSupportDir.appendingPathComponent("helper.pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return pid
    }

    func isCodexCallHelper(pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return false }
        return String(cString: buffer).hasSuffix("/codex-call-helper")
    }

    func ensureRouter() {
        guard !busy, !userStopped, componentsCurrent() else { return }
        if !isRouterRunning() { startRouter(silent: true) }
    }

    @objc func startRouterAction() {
        userStopped = false
        startRouter(silent: false)
    }

    func startRouter(silent: Bool) {
        guard componentsCurrent() else {
            if !silent { checkForUpdates() }
            return
        }
        guard !isRouterRunning() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath())
        process.arguments = ["run"]
        let logURL = URL(fileURLWithPath: "/tmp/codexcall-app.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
            helperProcess = process
        } catch {
            if !silent {
                setDisplayedStatus("Routing failed", detail: "Failed to start router: \(error)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshStatus() }
    }

    @objc func stopRouterAction() {
        userStopped = true
        stopRouter(silent: false)
    }

    func stopRouter(silent: Bool) {
        if let process = helperProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        } else if let pid = routerPID(), isCodexCallHelper(pid: pid), kill(pid, 0) == 0 {
            kill(pid, SIGTERM)
            for _ in 0..<20 where kill(pid, 0) == 0 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        helperProcess = nil
        runHelper(["restore"])
        if !silent { refreshStatus() }
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitAction() { NSApp.terminate(nil) }

    func refreshStatus() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let result = self.runHelper(["audio-status", "--json"])
            var values: [String: Any] = [:]
            if let data = result.output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                values = json
            }
            DispatchQueue.main.async { self.applyStatus(values) }
        }
    }

    func applyStatus(_ values: [String: Any]) {
        let rx = (values["virtualRX"] as? Bool) ?? false
        let tx = (values["virtualTX"] as? Bool) ?? false
        let clock = (values["virtualClock"] as? Bool) ?? false
        let running = isRouterRunning()
        let mode = (values["mode"] as? String) ?? "NORMAL"

        let current = rx && tx && clock && componentsCurrent()
        if !busy {
            if !current {
                setDisplayedStatus(
                    driverInstalled() ? "Update required" : "Not installed",
                    detail: "Use the signed macOS installer to install or update Codex Call."
                )
                setUpdateAction(title: "Install / Update…", enabled: true)
            } else if running {
                setDisplayedStatus(
                    "Routing active",
                    detail: "Codex voice is routed through Codex Virtual RX / TX."
                )
                setUpdateAction(title: "Check for Updates…", enabled: true)
            } else {
                setDisplayedStatus(
                    "Installed, routing stopped",
                    detail: "Click Start Routing to route Codex voice."
                )
                setUpdateAction(title: "Check for Updates…", enabled: true)
            }
        }

        let mic = (values["physicalInput"] as? String) ?? "unknown"
        let out = (values["physicalOutput"] as? String) ?? "unknown"
        modeLabel.stringValue = """
        Virtual RX: \(rx ? "OK" : "missing")
        Virtual TX: \(tx ? "OK" : "missing")
        Virtual Clock: \(clock ? "OK" : "missing")
        Mode: \(mode)
        Physical mic: \(mic)
        Physical output: \(out)
        Router: \(running ? "running" : "stopped")
        """
        statusItem.button?.image = NSImage(
            systemSymbolName: running ? "phone.fill" : "phone",
            accessibilityDescription: "Codex Call"
        )
        startButton.isEnabled = !busy && !running && current
        stopButton.isEnabled = running
        syncMenuActions()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
