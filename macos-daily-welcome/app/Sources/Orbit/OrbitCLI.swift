import Foundation

/// Where Orbit keeps things, and how to run its commands.
enum OrbitPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var stateDir: URL {
        if let custom = ProcessInfo.processInfo.environment["WELCOME_STATE_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return home.appendingPathComponent(".local/state/daily-welcome")
    }

    static var configDir: URL { home.appendingPathComponent(".config/daily-welcome") }
    static var config: URL { configDir.appendingPathComponent("config.sh") }
    static var macros: URL { configDir.appendingPathComponent("macros.conf") }
    static var contacts: URL { configDir.appendingPathComponent("contacts.conf") }

    static var memoryDir: URL { stateDir.appendingPathComponent("memory") }
    static var transcript: URL { memoryDir.appendingPathComponent("transcript.log") }
    static var facts: URL { memoryDir.appendingPathComponent("facts.txt") }
    static var events: URL { memoryDir.appendingPathComponent("events.log") }
    static var turns: URL { stateDir.appendingPathComponent("turns.log") }
    static var listenerStatus: URL { stateDir.appendingPathComponent("listener-status") }
    static var paused: URL { stateDir.appendingPathComponent("paused") }
    static var muted: URL { stateDir.appendingPathComponent("muted-until") }

    static var orbit: URL { home.appendingPathComponent(".local/bin/orbit") }
    static var welcome: URL { home.appendingPathComponent(".local/bin/daily-welcome") }

    /// The Orbit checkout the commands run from (~/.orbitai/macos-daily-welcome, usually).
    static var root: URL? {
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: orbit.path) else {
            return FileManager.default.fileExists(atPath: orbit.path)
                ? orbit.deletingLastPathComponent().deletingLastPathComponent() : nil
        }
        let target = URL(fileURLWithPath: resolved, relativeTo: orbit.deletingLastPathComponent()).standardizedFileURL
        return target.deletingLastPathComponent().deletingLastPathComponent()
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: orbit.path) }
}

/// Runs Orbit's command-line tools.
enum OrbitCLI {
    struct Result {
        let ok: Bool
        let output: String
    }

    /// What `orbit plan` answers with.
    struct Plan: Decodable {
        let speak: String
        let audio: String
        let confirm: Bool
        let token: String
        let end: Bool?
        let listen: Bool?
    }

    static func run(_ tool: URL, _ arguments: [String], timeout: TimeInterval = 90) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [tool.path] + arguments
                var env = ProcessInfo.processInfo.environment
                // Typed in the app, not heard by the microphone: the voice gate doesn't apply.
                env["ORBIT_FROM_CONSOLE"] = "1"
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + OrbitPaths.home.path + "/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = env
                let out = Pipe()
                process.standardOutput = out
                process.standardError = out
                do { try process.run() } catch {
                    continuation.resume(returning: Result(ok: false, output: error.localizedDescription))
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { usleep(30_000) }
                if process.isRunning { process.terminate() }
                process.waitUntilExit()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: Result(ok: process.terminationStatus == 0, output: text))
            }
        }
    }

    static func orbit(_ arguments: [String], timeout: TimeInterval = 90) async -> Result {
        await run(OrbitPaths.orbit, arguments, timeout: timeout)
    }

    static func welcome(_ arguments: [String], timeout: TimeInterval = 90) async -> Result {
        await run(OrbitPaths.welcome, arguments, timeout: timeout)
    }

    /// `orbit plan --chat`: what Orbit would say and do. Prints a JSON line last.
    static func plan(_ text: String) async -> (Plan?, String) {
        let result = await orbit(["plan", "--chat", text], timeout: 120)
        let last = result.output.split(separator: "\n").last.map(String.init) ?? ""
        let plan = try? JSONDecoder().decode(Plan.self, from: Data(last.utf8))
        return (plan, result.output)
    }

    static func confirm(_ token: String) async -> (Plan?, String) {
        let result = await orbit(["run", token], timeout: 120)
        let last = result.output.split(separator: "\n").last.map(String.init) ?? ""
        return (try? JSONDecoder().decode(Plan.self, from: Data(last.utf8)), result.output)
    }

    static func cancel(_ token: String) async {
        _ = await orbit(["cancel", token])
    }

    /// The effective value of each setting, as the shell itself resolves them.
    static func settingValues(_ keys: [String]) async -> [String: String] {
        guard let root = OrbitPaths.root else { return [:] }
        let prints = keys.map { "printf '%s\\t%s\\n' \($0) \"${\($0)}\"" }.joined(separator: "; ")
        let script = ". \"\(root.path)/lib/config.sh\"; welcome_load_user_config; \(prints)"
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", script]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                var values: [String: String] = [:]
                if (try? process.run()) != nil {
                    process.waitUntilExit()
                    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    for line in text.split(separator: "\n") {
                        let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                        if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
                    }
                }
                continuation.resume(returning: values)
            }
        }
    }

    /// Replaces one line in config.sh, leaving everything else alone (same as the web console).
    static func writeSetting(_ key: String, _ value: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: OrbitPaths.configDir, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: OrbitPaths.config, encoding: .utf8)) ?? "# daily-welcome settings\n"
        var lines = existing.components(separatedBy: "\n").filter { !$0.hasPrefix("\(key)=") }
        while lines.last == "" { lines.removeLast() }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        lines.append("\(key)=\"\(escaped)\"")
        try? (lines.joined(separator: "\n") + "\n").write(to: OrbitPaths.config, atomically: true, encoding: .utf8)
    }
}
