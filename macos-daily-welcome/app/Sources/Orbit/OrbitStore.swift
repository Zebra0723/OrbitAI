import AppKit

// MARK: - Records

/// One thing said, by you or by Orbit.
struct Turn: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id: Int
    let role: Role
    let date: Date
    let text: String
}

/// Something Orbit did ("Messaged Mama", "Added a reminder").
struct Event: Identifiable, Equatable {
    let id: Int
    let date: Date
    let kind: String
    let summary: String
}

/// A stretch of talking with no long gap and no "forget that" in the middle.
struct Session: Identifiable, Equatable {
    let id: Int
    let turns: [Turn]
    var start: Date { turns.first?.date ?? .distantPast }
    var end: Date { turns.last?.date ?? .distantPast }
    var title: String {
        let first = turns.first(where: { $0.role == .user })?.text ?? "Conversation"
        return first.count > 70 ? String(first.prefix(70)) + "…" : first
    }
}

struct Fact: Identifiable, Equatable {
    let id: Int
    let date: String
    let text: String
    /// The exact line in facts.txt, so deleting removes this one and no other.
    let line: String
}

/// "phrase = command; command" from macros.conf, or "name = +1555…" from contacts.conf.
struct ConfEntry: Identifiable, Equatable {
    var id: String { name.lowercased() }
    var name: String
    var value: String
}

/// Whether Orbit may make a sound. Mirrors orbit_muted in lib/common.sh.
enum MuteState: Equatable {
    case off
    case untilUnmuted
    case until(Date)

    var isMuted: Bool { self != .off }

    static func read() -> MuteState {
        guard FileManager.default.fileExists(atPath: OrbitPaths.muted.path) else { return .off }
        let text = ((try? String(contentsOf: OrbitPaths.muted, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Anything unreadable counts as muted, the same as the shell.
        guard text != "never", let epoch = TimeInterval(text) else { return .untilUnmuted }
        let end = Date(timeIntervalSince1970: epoch)
        return end > Date() ? .until(end) : .off
    }

    var description: String {
        switch self {
        case .off: return "Sound on"
        case .untilUnmuted: return "Muted until you unmute"
        case .until(let end):
            let clock = Format.clock(end)
            return Calendar.current.isDateInToday(end) ? "Muted until \(clock)" : "Muted until \(Format.day(end)) \(clock)"
        }
    }
}

struct ListenerStatus: Equatable {
    var state = "unknown"
    var updated = ""
    var wake = ""
    var appRunning = false
    var paused = false
}

// MARK: - Store

/// Everything Orbit has on disk, read straight from its files and refreshed
/// while the app is open. Orbit's shell scripts stay the only writers of the
/// logs; the app edits only memory facts, macros, contacts, and settings.
@MainActor
final class OrbitStore: ObservableObject {
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var events: [Event] = []
    @Published private(set) var facts: [Fact] = []
    @Published private(set) var macros: [ConfEntry] = []
    @Published private(set) var contacts: [ConfEntry] = []
    @Published private(set) var listener = ListenerStatus()
    @Published private(set) var mute = MuteState.off

    private var refreshTask: Task<Void, Never>?
    private var stamps: [URL: Date] = [:]

    init() {
        reload(force: true)
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.reload(force: false)
            }
        }
    }

    /// Re-reads any file that changed since last time.
    func reload(force: Bool) {
        if force || changed(OrbitPaths.transcript) {
            turns = Self.readTurns()
            sessions = Self.group(turns)
        }
        if force || changed(OrbitPaths.events) { events = Self.readEvents() }
        if force || changed(OrbitPaths.facts) { facts = Self.readFacts() }
        if force || changed(OrbitPaths.macros) { macros = Self.readConf(OrbitPaths.macros) }
        if force || changed(OrbitPaths.contacts) { contacts = Self.readConf(OrbitPaths.contacts) }
        listener = Self.readListener()
        mute = MuteState.read()
    }

    // MARK: Mute

    /// "" mutes until unmuted; otherwise anything `orbit mute` reads: 45m, 2h, until 7:30.
    @discardableResult
    func mute(for length: String) async -> Bool {
        let trimmed = length.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await OrbitCLI.orbit(trimmed.isEmpty ? ["mute"] : ["mute", trimmed])
        reload(force: false)
        return result.ok
    }

    func unmute() async {
        _ = await OrbitCLI.orbit(["unmute"])
        reload(force: false)
    }

    private func changed(_ url: URL) -> Bool {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        defer { stamps[url] = modified ?? .distantPast }
        return stamps[url] != (modified ?? .distantPast)
    }

    // MARK: Memory

    func addFact(_ text: String) async {
        let fact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fact.isEmpty else { return }
        _ = await OrbitCLI.orbit(["memory", "add", fact])
        reload(force: true)
    }

    func deleteFact(_ fact: Fact) {
        guard let text = try? String(contentsOf: OrbitPaths.facts, encoding: .utf8) else { return }
        var removed = false
        let kept = text.components(separatedBy: "\n").filter { line in
            if !removed && line == fact.line { removed = true; return false }
            return true
        }
        try? kept.joined(separator: "\n").write(to: OrbitPaths.facts, atomically: true, encoding: .utf8)
        reload(force: true)
    }

    func clearFacts() {
        try? "".write(to: OrbitPaths.facts, atomically: true, encoding: .utf8)
        reload(force: true)
    }

    // MARK: Macros and people

    func saveMacros(_ entries: [ConfEntry]) {
        Self.writeConf(entries, to: OrbitPaths.macros, header: """
        # Orbit macros: one phrase, several commands, separated by semicolons.
        #   good night = dark mode; turn off wifi; set a timer for 5 minutes
        """)
        reload(force: true)
    }

    func saveContacts(_ entries: [ConfEntry]) {
        Self.writeConf(entries, to: OrbitPaths.contacts, header: """
        # Orbit nicknames: who you mean when you say a name.
        #   mama = +15551234567
        """)
        reload(force: true)
    }

    // MARK: Listening

    func setListening(_ on: Bool) async {
        _ = await OrbitCLI.orbit(["listen", on ? "resume" : "pause"])
        reload(force: false)
    }

    // MARK: - Parsing

    private static let minuteFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func lines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private static func fields(_ line: String) -> [String] {
        line.components(separatedBy: "\t")
    }

    /// transcript.log: role<TAB>YYYY-MM-DD HH:MM<TAB>text (old lines have no date).
    /// A "reset" row marks "forget that" and splits sessions.
    private static func readTurns() -> [Turn] {
        var result: [Turn] = []
        var lastDate = Date.distantPast
        for (index, line) in lines(OrbitPaths.transcript).enumerated() {
            let parts = fields(line)
            guard let role = parts.first else { continue }
            if role == "reset" {
                result.append(Turn(id: index, role: .user, date: lastDate, text: "\u{0}reset"))
                continue
            }
            guard let parsed = Turn.Role(rawValue: role) else { continue }
            let date = parts.count >= 3 ? (minuteFormat.date(from: parts[1]) ?? lastDate) : lastDate
            let text = parts.count >= 3 ? parts[2...].joined(separator: "\t") : (parts.count == 2 ? parts[1] : "")
            lastDate = date
            result.append(Turn(id: index, role: parsed, date: date, text: text))
        }
        return result
    }

    /// Sessions break at a "forget that" or after 30 quiet minutes. Newest first.
    private static func group(_ turns: [Turn]) -> [Session] {
        var sessions: [Session] = []
        var current: [Turn] = []
        func close() {
            if current.contains(where: { $0.role == .user }) {
                sessions.append(Session(id: current.first?.id ?? sessions.count, turns: current))
            }
            current = []
        }
        for turn in turns {
            if turn.text == "\u{0}reset" { close(); continue }
            if let last = current.last, turn.date.timeIntervalSince(last.date) > 30 * 60 { close() }
            current.append(turn)
        }
        close()
        return sessions.reversed()
    }

    /// events.log: YYYY-MM-DD HH:MM<TAB>kind<TAB>summary
    private static func readEvents() -> [Event] {
        lines(OrbitPaths.events).enumerated().compactMap { index, line in
            let parts = fields(line)
            guard parts.count >= 3, let date = minuteFormat.date(from: parts[0]) else { return nil }
            return Event(id: index, date: date, kind: parts[1], summary: parts[2...].joined(separator: "\t"))
        }
    }

    /// facts.txt: YYYY-MM-DD<TAB>fact. Newest first.
    private static func readFacts() -> [Fact] {
        lines(OrbitPaths.facts).enumerated().compactMap { index, line in
            let parts = fields(line)
            if parts.count >= 2 { return Fact(id: index, date: parts[0], text: parts[1...].joined(separator: " "), line: line) }
            return Fact(id: index, date: "", text: line, line: line)
        }.reversed()
    }

    /// "name = value" lines; comments and blanks skipped.
    private static func readConf(_ url: URL) -> [ConfEntry] {
        lines(url).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { return nil }
            let name = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return ConfEntry(name: name, value: value)
        }
    }

    private static func writeConf(_ entries: [ConfEntry], to url: URL, header: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = entries
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.name.trimmingCharacters(in: .whitespaces)) = \($0.value.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")
        try? (header + "\n\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func readListener() -> ListenerStatus {
        var status = ListenerStatus()
        for line in lines(OrbitPaths.listenerStatus) {
            let parts = fields(line)
            guard parts.count >= 2 else { continue }
            switch parts[0] {
            case "state": status.state = parts[1]
            case "updated": status.updated = parts[1]
            case "wake": status.wake = parts[1]
            default: break
            }
        }
        status.paused = FileManager.default.fileExists(atPath: OrbitPaths.paused.path)
        status.appRunning = NSWorkspace.shared.runningApplications.contains {
            $0.executableURL?.lastPathComponent == "DailyWelcome"
        }
        return status
    }
}
