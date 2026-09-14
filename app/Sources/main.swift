import AppKit
import AVFoundation

let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/CodexCall", isDirectory: true)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!

    let stateLabel = NSTextField(labelWithString: "Checking…")
    let detailLabel = NSTextField(labelWithString: "")
    let modeLabel = NSTextField(labelWithString: "")
    let installButton = NSButton(title: "Install", target: nil, action: nil)
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
            self?.installIfNeeded()
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
        statusMenu.addItem(NSMenuItem(title: "Show Codex Call", action: #selector(showWindow), keyEquivalent: ""))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Start Routing", action: #selector(startRouterAction), keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Stop Routing", action: #selector(stopRouterAction), keyEquivalent: ""))
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

    func helperPath() -> String {
        if let path = Bundle.main.path(forResource: "codex-call-helper", ofType: nil) {
            return path
        }
        return "/usr/local/bin/codex-call-helper"
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

    func installIfNeeded() {
        removeLaunchAgent()
        if driverInstalled() {
            if helperNeedsUpdate() { refreshHelper() }
            refreshStatus()
            if !isRouterRunning() { startRouter(silent: true) }
        } else {
            install()
        }
    }

    @objc func installAction() { install() }

    func install() {
        guard !busy else { return }
        busy = true
        installButton.isEnabled = false
        stateLabel.stringValue = "Installing…"
        detailLabel.stringValue = "macOS will ask for your password to install the virtual audio driver."
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            let ok = self.performInstall()
            DispatchQueue.main.async {
                self.busy = false
                self.installButton.isEnabled = true
                if ok {
                    self.runHelper(["setup"])
                    self.startRouter(silent: true)
                }
                self.refreshStatus()
            }
        }
    }

    @discardableResult
    func runPrivileged(_ script: String) -> Bool {
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("codexcall-priv.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let appleScript = "do shell script \"/bin/sh '\(scriptURL.path)'\" with administrator privileges"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", appleScript]
        do {
            try osa.run()
            osa.waitUntilExit()
        } catch {
            return false
        }
        return osa.terminationStatus == 0
    }

    func helperNeedsUpdate() -> Bool {
        let installed = "/usr/local/bin/codex-call-helper"
        let fm = FileManager.default
        guard let a = try? fm.attributesOfItem(atPath: installed)[.size] as? Int,
              let b = try? fm.attributesOfItem(atPath: helperPath())[.size] as? Int else {
            return true
        }
        return a != b
    }

    func refreshHelper() {
        guard let helper = Bundle.main.path(forResource: "codex-call-helper", ofType: nil) else { return }
        let script = """
        set -e
        mkdir -p /usr/local/lib/codex-call /usr/local/bin
        cp "\(helper)" /usr/local/lib/codex-call/codex-call-helper
        cp "\(helper)" /usr/local/bin/codex-call-helper
        chmod 755 /usr/local/lib/codex-call/codex-call-helper /usr/local/bin/codex-call-helper
        """
        runPrivileged(script)
    }

    func performInstall() -> Bool {
        guard let resources = Bundle.main.resourceURL else { return false }
        let driverRX = resources.appendingPathComponent("driver/CodexVirtualRX.driver")
        let driverTX = resources.appendingPathComponent("driver/CodexVirtualTX.driver")
        let driverClock = resources.appendingPathComponent("driver/CodexVirtualClock.driver")
        let helper = resources.appendingPathComponent("codex-call-helper")
        let plugin = resources.appendingPathComponent("plugin")

        let script = """
        set -e
        mkdir -p /Library/Audio/Plug-Ins/HAL
        rm -rf "/Library/Audio/Plug-Ins/HAL/CodexVirtualRX.driver" "/Library/Audio/Plug-Ins/HAL/CodexVirtualTX.driver" "/Library/Audio/Plug-Ins/HAL/CodexVirtualClock.driver"
        cp -R "\(driverRX.path)" /Library/Audio/Plug-Ins/HAL/
        cp -R "\(driverTX.path)" /Library/Audio/Plug-Ins/HAL/
        cp -R "\(driverClock.path)" /Library/Audio/Plug-Ins/HAL/
        chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/CodexVirtualRX.driver" "/Library/Audio/Plug-Ins/HAL/CodexVirtualTX.driver" "/Library/Audio/Plug-Ins/HAL/CodexVirtualClock.driver"
        mkdir -p /usr/local/lib/codex-call /usr/local/bin
        cp "\(helper.path)" /usr/local/lib/codex-call/codex-call-helper
        cp "\(helper.path)" /usr/local/bin/codex-call-helper
        chmod 755 /usr/local/lib/codex-call/codex-call-helper /usr/local/bin/codex-call-helper
        launchctl kickstart -k system/com.apple.audio.coreaudiod >/dev/null 2>&1 || true
        """
        if !runPrivileged(script) { return false }

        removeLaunchAgent()
        installPlugin(plugin: plugin)
        return true
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
        let pidFile = appSupportDir.appendingPathComponent("helper.pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == 0
    }

    func ensureRouter() {
        guard !busy, !userStopped, driverInstalled() else { return }
        if !isRouterRunning() { startRouter(silent: true) }
    }

    @objc func startRouterAction() {
        userStopped = false
        startRouter(silent: false)
    }

    func startRouter(silent: Bool) {
        guard driverInstalled() else {
            if !silent { install() }
            return
        }
        guard !isRouterRunning() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath())
        process.arguments = ["run"]
        let logURL = URL(fileURLWithPath: "/tmp/codexcall-app.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            try process.run()
            helperProcess = process
        } catch {
            if !silent { detailLabel.stringValue = "Failed to start router: \(error)" }
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
        let running = isRouterRunning()
        let mode = (values["mode"] as? String) ?? "NORMAL"

        if !rx || !tx {
            stateLabel.stringValue = "Not installed"
            detailLabel.stringValue = "Click Install to set up the virtual audio driver and helper."
            installButton.isHidden = false
        } else if running {
            stateLabel.stringValue = "Routing active"
            detailLabel.stringValue = "Codex voice is routed through Codex Virtual RX / TX."
            installButton.isHidden = true
        } else {
            stateLabel.stringValue = "Installed, routing stopped"
            detailLabel.stringValue = "Click Start Routing to route Codex voice."
            installButton.isHidden = true
        }

        let mic = (values["physicalInput"] as? String) ?? "unknown"
        let out = (values["physicalOutput"] as? String) ?? "unknown"
        modeLabel.stringValue = """
        Virtual RX: \(rx ? "OK" : "missing")
        Virtual TX: \(tx ? "OK" : "missing")
        Mode: \(mode)
        Physical mic: \(mic)
        Physical output: \(out)
        Router: \(running ? "running" : "stopped")
        """
        statusItem.button?.image = NSImage(
            systemSymbolName: running ? "phone.fill" : "phone",
            accessibilityDescription: "Codex Call"
        )
        startButton.isEnabled = !running && rx && tx
        stopButton.isEnabled = running
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
