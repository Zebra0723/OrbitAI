// DailyWelcome - a menu bar agent for macOS.
//
// It owns no windows and has no Dock icon (LSUIElement). Its whole job is
// to notice that the Mac just came back to life and hand off to the
// daily-welcome shell script, which decides whether today's greeting is
// still owed.
//
// Waking is watched three ways, because no single one covers every case:
//   - didWake / screensDidWake     lid opened, machine resumed
//   - com.apple.screenIsUnlocked   you actually unlocked it
//   - a 5-minute backstop timer    a wake we somehow missed

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var lastRunItem: NSMenuItem!
    private var backstopTimer: Timer?

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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "sun.horizon",
                                   accessibilityDescription: "Daily Welcome") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "\u{2600}"
            }
            button.toolTip = "Daily Welcome"
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

        backstopTimer = Timer.scheduledTimer(timeInterval: 300, target: self,
                                             selector: #selector(backstopTick),
                                             userInfo: nil, repeats: true)

        // Give the desktop a beat to settle before the first check at login.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.run(["--agent"])
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        backstopTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Triggers

    @objc private func machineCameBack(_ note: Notification) {
        // Unlock and wake usually arrive together; the script's once-a-day
        // stamp and lock directory make the duplicate call harmless.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.run(["--agent"])
        }
    }

    @objc private func backstopTick() { run(["--agent"]) }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        lastRunItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        lastRunItem.isEnabled = false
        menu.addItem(lastRunItem)
        menu.addItem(.separator())

        menu.addItem(item("Play Today's Briefing", #selector(playBriefing), "p"))
        menu.addItem(item("Show Briefing Only", #selector(showBriefing), "s"))
        menu.addItem(item("Speak Briefing Only", #selector(speakBriefing), ""))
        menu.addItem(.separator())

        menu.addItem(item("Mute for Today", #selector(muteToday), ""))
        menu.addItem(item("Greet Me Again Today", #selector(resetToday), ""))
        menu.addItem(.separator())

        menu.addItem(item("Edit Settings\u{2026}", #selector(editSettings), ","))
        menu.addItem(item("Open Log", #selector(openLog), ""))
        menu.addItem(.separator())

        menu.addItem(item("Quit Daily Welcome", #selector(quit), "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    func menuWillOpen(_ menu: NSMenu) { refreshLastRunItem() }

    private func refreshLastRunItem() {
        let stamp = (try? String(contentsOfFile: stateDir + "/last-run", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stamp == Self.todayStamp() {
            lastRunItem.title = "Greeted today"
        } else if stamp.isEmpty {
            lastRunItem.title = "Waiting for the first greeting"
        } else {
            lastRunItem.title = "Last greeting: \(stamp)"
        }
    }

    private static func todayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Actions

    @objc private func playBriefing()  { run(["--force"]) }
    @objc private func showBriefing()  { run(["--preview", "--quiet"]) }
    @objc private func speakBriefing() { run(["--preview", "--present", "stdout"]) }
    @objc private func muteToday()     { run(["--mute-today"]) }
    @objc private func resetToday()    { run(["--reset"]) }

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

    @objc private func quit() { NSApp.terminate(nil) }

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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no windows
app.run()
