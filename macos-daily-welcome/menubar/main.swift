// DailyWelcome - Orbit's menu bar app for macOS.
//
// It owns no windows and has no Dock icon (LSUIElement). It listens for the
// wake word and hands what you say to the orbit shell script. Orbit only
// ever speaks in answer to someone: nothing here talks on a timer, on wake,
// or on unlock.
//
// Waking is still watched, but only to bring the microphone back:
//   - didWake / screensDidWake     lid opened, machine resumed
//   - com.apple.screenIsUnlocked   you actually unlocked it

import Cocoa
import EventKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var listeningItem: NSMenuItem!
    /// The console server, once it has been asked for.
    private var consoleTask: Process?
    private let listener = OrbitListener()

    // MARK: - Paths

    /// Written into Info.plist by the installer; overridable by the launch agent.
    private var scriptPath: String {
        let env = ProcessInfo.processInfo.environment["DAILY_WELCOME_BIN"] ?? ""
        if !env.isEmpty { return env }
        if let p = Bundle.main.object(forInfoDictionaryKey: "DWScriptPath") as? String, !p.isEmpty {
            return (p as NSString).expandingTildeInPath
        }
        return ("~/.local/bin/daily-welcome" as NSString).expandingTildeInPath
    }

    private var stateDir: String {
        let env = ProcessInfo.processInfo.environment["WELCOME_STATE_DIR"] ?? ""
        if !env.isEmpty { return env }
        return ("~/.local/state/daily-welcome" as NSString).expandingTildeInPath
    }

    private var configPath: String {
        ("~/.config/daily-welcome/config.sh" as NSString).expandingTildeInPath
    }

    private var logPath: String { stateDir + "/agent.log" }

    private var orbitPath: String {
        let env = ProcessInfo.processInfo.environment["ORBIT_BIN"] ?? ""
        if !env.isEmpty { return env }
        if let p = Bundle.main.object(forInfoDictionaryKey: "DWOrbitPath") as? String, !p.isEmpty {
            return (p as NSString).expandingTildeInPath
        }
        return ("~/.local/bin/orbit" as NSString).expandingTildeInPath
    }

    /// Settings live in the shell config; asking for them keeps this app
    /// from holding a second copy that drifts out of date.
    private func shellConfig(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [orbitPath, "config", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private lazy var wakeWord: String = {
        (shellConfig("wake_word") ?? "hey orbit").lowercased()
    }()

    private lazy var listeningWanted: Bool = {
        (shellConfig("listen") ?? "1") != "0"
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "circle.circle",
                                   accessibilityDescription: "Orbit") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Orbit"
            }
            button.toolTip = "Orbit"
        }
        statusItem.menu = buildMenu()

        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.didWakeNotification,
                                          NSWorkspace.screensDidWakeNotification,
                                          NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(machineCameBack(_:)),
                                  name: name, object: nil)
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(machineCameBack(_:)),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        listener.orbitPath = orbitPath
        listener.wakeWord = wakeWord
        listener.statusPath = stateDir + "/listener-status"
        listener.wakeAliases = (shellConfig("aliases") ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if let seconds = Double(shellConfig("followup") ?? ""), seconds > 0 {
            listener.followUpWindow = seconds
        }
        if let seconds = Double(shellConfig("conversation_seconds") ?? ""), seconds > 0 {
            listener.conversationWindow = seconds
        }
        listener.conversationMode = (shellConfig("conversation") ?? "1") != "0"
        listener.onDeviceOnly = (shellConfig("ondevice") ?? "1") != "0"
        if let threshold = Double(shellConfig("wake_threshold") ?? ""), threshold > 0 {
            listener.wakeThreshold = threshold
        }
        listener.heardLogPath = stateDir + "/heard.log"
        listener.pausePath = stateDir + "/paused"
        listener.callPath = stateDir + "/on-call"
        listener.utterancePath = stateDir + "/utterance.wav"
        listener.bypassPath = stateDir + "/bypass"
        listener.enrollPath = stateDir + "/enrolling"
        listener.keepUtteranceAudio = (shellConfig("speaker_id") ?? "0") != "0"
        listener.pauseOnCall = (shellConfig("pause_on_call") ?? "1") != "0"
        CallWatch.ignoredBundleIDs = Set((shellConfig("call_ignore") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        listener.wantsToListen = listeningWanted
        listener.onStateChange = { [weak self] state in
            self?.reflect(state)
        }
        if listeningWanted {
            listener.start()
        }

        // Option-Space by default: near the space bar, not taken by much.
        if (shellConfig("hotkey") ?? "1") != "0" {
            listener.installHotKey(49, flags: .option)   // 49 is Space
        }
    }

    /// The icon says what Orbit is doing, so an open microphone is never
    /// something you have to take on trust.
    private func reflect(_ state: ListenState) {
        let symbol: String
        switch state {
        case .idle:       symbol = "sun.horizon"
        case .capturing:  symbol = "waveform"
        case .confirming: symbol = "questionmark.circle"
        case .working:    symbol = "gearshape"
        case .speaking:   symbol = "speaker.wave.2"
        }
        if let button = statusItem.button,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Daily Welcome") {
            image.isTemplate = true
            button.image = image
        }
        listeningItem?.state = listener.isRunning ? .on : .off
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Triggers

    @objc private func machineCameBack(_ note: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            // Sleep is where the microphone usually gets lost.
            self?.listener.restartIfNeeded()
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(item("Listen Now (\u{2325}Space)", #selector(listenNow), "l"))
        listeningItem = item("Listening for \u{201C}\(wakeWord)\u{201D}", #selector(toggleListening), "")
        listeningItem.state = listeningWanted ? .on : .off
        menu.addItem(listeningItem)
        menu.addItem(.separator())

        menu.addItem(item("Stop Talking", #selector(hush), "."))
        menu.addItem(.separator())

        // Everything the terminal could do, on a page. Reaching it used
        // to mean opening Terminal and typing `orbit console`, which is
        // the whole barrier for anybody who does not already live there.
        menu.addItem(item("Settings and Setup\u{2026}", #selector(openConsole), ","))
        menu.addItem(item("Edit the Settings File\u{2026}", #selector(editSettings), ""))
        menu.addItem(item("Open Log", #selector(openLog), ""))
        menu.addItem(.separator())

        menu.addItem(item("Quit Orbit", #selector(quit), "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    // MARK: - Actions

    @objc private func hush()          { run(["--hush"]) }

    @objc private func listenNow() { listener.listenNow() }

    @objc private func toggleListening() {
        if listener.isRunning {
            listener.stop()
            listeningItem.state = .off
        } else {
            listener.start()
            listeningItem.state = .on
        }
    }


    /// Starts the console and opens it.
    ///
    /// Served from this Mac, so the page is same-origin: no address to
    /// type, no token to paste, nothing to understand about ports. It
    /// stays running until the app quits.
    @objc private func openConsole() {
        if consoleTask == nil || !(consoleTask?.isRunning ?? false) {
            // `orbit console` serves the page AND opens it, so there is
            // no address to type and no port to know about.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [orbitPath, "console"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            consoleTask = task
        } else {
            // Already running from a previous click; just bring it up.
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["http://127.0.0.1:7717/"]
            try? open.run()
        }
    }

    @objc private func editSettings() {
        let path = configPath
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true)
            try? "# daily-welcome settings\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func openLog() {
        let path = logPath
        if !FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Leaves nothing running behind it.
    private func stopConsole() {
        if let task = consoleTask, task.isRunning { task.terminate() }
        consoleTask = nil
    }

    @objc private func quit() {
        stopConsole()
        NSApp.terminate(nil)
    }

    // MARK: - Running the script

    private func run(_ arguments: [String]) {
        let path = scriptPath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            NSLog("daily-welcome: no executable script at \(path)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLastRunItem() }
        }
        do { try process.run() } catch {
            NSLog("daily-welcome: could not run \(path): \(error.localizedDescription)")
        }
    }
}

// Data-dump modes run headless and exit: same binary, same code signature,
// so the permissions belong to the app whichever way it was started.
switch CommandLine.arguments.dropFirst().first {
case "--dump-reminders": dumpReminders()
case "--dump-events":    dumpEvents()
default: break
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no windows
app.run()
