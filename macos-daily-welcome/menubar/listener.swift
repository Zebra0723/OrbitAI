// The ears.
//
// One continuous on-device recognition task listens for the wake word.
// Hearing it, the listener starts a fresh task for the command itself,
// ends that on a beat of silence, and hands the sentence to `orbit plan`.
// If the plan needs confirming, the same loop listens for yes or no.
//
// Recognition is on-device where the Mac supports it, so audio doesn't
// leave the machine. The engine is stopped whenever Orbit is speaking,
// both to save it hearing itself and so "no" can't be triggered by its
// own question.

import Cocoa
import AVFoundation
import Speech

enum ListenState {
    case idle          // waiting for the wake word
    case capturing     // collecting the command
    case confirming    // waiting for yes or no
    case working       // running something; not listening
    case speaking      // talking, listening only for "stop"
}

final class OrbitListener: NSObject {

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var state: ListenState = .idle
    private var stateSince = Date()
    private var heard = ""
    private var lastHeardAt = Date()
    /// The wake word as it was actually heard, so it can be stripped off
    /// the front of the command that follows it in the same breath.
    private var wakePrefix = ""
    /// What Orbit is currently saying, so its own words can't interrupt it.
    private var speakingText = ""
    private var player: AVAudioPlayer?
    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var pendingToken = ""

    /// Path to the `orbit` script; set by the app delegate.
    var orbitPath: String = ""
    var wakeWord: String = "hey orbit"
    /// Where to leave a note about what the ears are doing. A menu bar app
    /// has nowhere to show an error, so `doctor` reads this instead.
    var statusPath: String = ""

    /// The distinctive part of the wake phrase. Recognisers drop the "hey"
    /// far more often than they drop the name.
    private var wakeKey: String {
        wakeWord.split(separator: " ").last.map(String.init) ?? wakeWord
    }

    private var lastLogged = ""
    private var lastStatus = ""
    private var lastStatusWrite = Date.distantPast

    /// Words the commands are built from. Given to the recogniser as
    /// context so short instructions aren't reinterpreted as prose.
    private let commandVocabulary = [
        "brief me", "mute", "unmute", "volume up", "volume down",
        "take a screenshot", "lock my Mac", "what time is it",
        "read my messages", "what's on my calendar", "hang up",
        "set a timer", "remind me to", "message", "FaceTime", "Claude",
    ]

    /// Extra spellings that count as the wake word. Recognisers hear a
    /// made-up name as whatever real words it resembles, and those
    /// mishearings are consistent enough to just accept.
    var wakeAliases: [String] = []

    /// How close a heard word has to be to the name to count. 0.6 accepts
    /// "orbid" and "or bit" while still rejecting ordinary conversation.
    var wakeThreshold: Double = 0.6

    /// On-device recognition keeps audio on the Mac but is markedly worse
    /// at words it has never seen - which a made-up name always is.
    var onDeviceOnly = true

    /// Everything heard while idle, most recent last. The only way to know
    /// what the recogniser is actually making of you.
    var heardLogPath: String = ""

    /// Called with the current state so the menu bar icon can reflect it.
    var onStateChange: ((ListenState) -> Void)?

    /// How long a pause ends the command. Every millisecond here is dead
    /// air before Orbit even starts thinking, so it's as short as it can be
    /// without cutting people off mid-sentence.
    private let commandSilence: TimeInterval = 0.9
    private let confirmTimeout: TimeInterval = 12
    private var confirmStartedAt = Date()
    /// How long a working or speaking state may last before it's treated
    /// as hung. Long enough for a slow Mail query, short enough that you
    /// don't stand there wondering.
    private let stuckLimit: TimeInterval = 45

    /// Seconds to keep listening after answering a bare wake word.
    var followUpWindow: TimeInterval = 9

    /// Once a conversation has started, the wake word is not needed again
    /// until it ends - either because you said so, or because nothing has
    /// been said for this long.
    var conversationMode = true
    var conversationWindow: TimeInterval = 25
    private var inConversation = false
    /// True once the wake word has been acknowledged on its own, so the
    /// greeting happens at most once per wake rather than on a loop.
    private var greeted = false

    // MARK: - Permissions and lifecycle

    func start() {
        guard recognizer != nil else {
            status("no-recognizer", "Speech recognition isn't available for en-US on this Mac")
            return
        }
        status("asking", "waiting for permission")

        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard let self = self else { return }
            guard auth == .authorized else {
                self.status("speech-denied",
                            "Speech Recognition is off for this app (Privacy & Security > Speech Recognition)")
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    self.status("mic-denied",
                                "Microphone is off for this app (Privacy & Security > Microphone)")
                    return
                }
                DispatchQueue.main.async { self.beginSession() }
            }
        }
    }

    /// Leaves a one-line note about the ears where `doctor` can find it.
    private func status(_ state: String, _ detail: String = "", heard: String? = nil) {
        guard !statusPath.isEmpty else { return }
        // Partial transcripts arrive several times a second; the file is a
        // diagnostic, not a log, so it's rewritten at most every two seconds
        // unless the state itself changed.
        if state == lastStatus, heard != nil, Date().timeIntervalSince(lastStatusWrite) < 2 { return }
        lastStatus = state
        lastStatusWrite = Date()

        let stamp = ISO8601DateFormatter().string(from: Date())
        var text = "state\t\(state)\nupdated\t\(stamp)\nwake\t\(wakeWord)\n"
        if !detail.isEmpty { text += "detail\t\(detail)\n" }
        if let heard = heard, !heard.isEmpty { text += "heard\t\(heard)\n" }
        try? text.write(toFile: statusPath, atomically: true, encoding: .utf8)
    }

    func stop() {
        silenceTimer?.invalidate()
        restartTimer?.invalidate()
        endRecognition()
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        setState(.idle)
    }

    var isRunning: Bool { engine.isRunning }

    /// Tears the audio down and builds it again. Cheap, and the only
    /// reliable cure for an engine that has quietly stopped.
    func restartSession(reason: String) {
        status("restarting", reason)
        silenceTimer?.invalidate()
        restartTimer?.invalidate()
        endRecognition()
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        greeted = false
        heard = ""
        setState(.idle)
        // A beat, so the device that just changed has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.beginSession()
        }
    }

    /// Called on wake and unlock: if the ears died while the Mac slept,
    /// this is the moment to notice.
    func restartIfNeeded() {
        guard !engine.isRunning else { return }
        restartSession(reason: "not running after wake")
    }

    /// Skips the wake word - used by the menu item.
    func listenNow() {
        guard engine.isRunning else { start(); return }
        heard = ""
        greeted = false
        lastHeardAt = Date()
        setState(.capturing)
        restartRecognition()
        chime("Tink")
    }

    // MARK: - Audio

    private func beginSession() {
        guard !engine.isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            status("audio-failed", error.localizedDescription)
            return
        }
        status("listening", "waiting for \"\(wakeWord)\"")

        restartRecognition()

        // A recognition task is capped at around a minute, so it gets
        // recycled well before it expires rather than dying mid-sentence.
        // The audio engine stops on its own more often than you'd like -
        // sleep, a headphone plugged in, an input device changing - and it
        // does it silently, which is exactly what "it stopped listening
        // and I don't know why" looks like from outside.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak self] _ in
                self?.restartSession(reason: "audio device changed")
        }

        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Watchdog first: a dead engine is worth noticing within a
            // minute rather than the next time you happen to talk to it.
            if !self.engine.isRunning {
                self.restartSession(reason: "engine had stopped")
                return
            }
            guard self.state == .idle else { return }
            self.restartRecognition()
        }

        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.checkSilence()
        }

        setState(.idle)
    }

    private func endRecognition() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
    }

    private func restartRecognition() {
        endRecognition()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if onDeviceOnly, #available(macOS 13.0, *), recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        // A made-up name is not in any language model, so it comes back as
        // whatever real words it sounded like. Contextual strings tell the
        // recogniser these are words worth expecting.
        req.contextualStrings = [wakeWord, wakeKey, wakeKey.capitalized,
                                 "Hey \(wakeKey.capitalized)"] + commandVocabulary
        req.taskHint = .dictation
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.handle(transcript: result.bestTranscription.formattedString)
            }
            // A task that dies mid-command used to leave the ears deaf
            // until the next wake word that never got heard. Restart it
            // whatever state we're in.
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    guard self.state != .working else { return }
                    self.restartRecognition()
                }
            }
        }
    }

    // MARK: - Understanding

    private func handle(transcript raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let lower = text.lowercased()

        switch state {
        case .idle:
            guard let range = wakeRange(in: lower) else {
                // Not the wake word - but worth recording, because "it isn't
                // hearing me" and "it hears me as something else" look
                // identical from the outside and need different fixes.
                status("listening", "waiting for \"\(wakeWord)\"", heard: lower)
                logHeard(lower)
                return
            }
            // Anything said after the wake word in the same breath counts
            // as the command, so "Hey Orbit, mute" works in one go.
            let tail = String(text[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            status("woken", "heard the wake word", heard: lower)
            greeted = false
            lastHeardAt = Date()
            setState(.capturing)
            chime("Tink")

            if tail.isEmpty {
                // Nothing said in the same breath: start a clean task so the
                // command isn't reported back with the wake word glued to
                // the front of it.
                heard = ""
                restartRecognition()
            } else {
                heard = tail
                wakePrefix = String(text[..<range.upperBound])
            }

        case .capturing:
            // The recogniser reports the whole utterance each time, wake
            // word included when it was said in one breath. Strip it, or
            // the command handed on starts with "hey orbit".
            if !wakePrefix.isEmpty, lower.hasPrefix(wakePrefix) {
                heard = String(text.dropFirst(wakePrefix.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            } else {
                heard = text
            }
            lastHeardAt = Date()

        case .confirming:
            if let answer = yesOrNo(in: lower) {
                setState(.working)
                answer ? runPending() : cancelPending()
                return
            }
            // Not a yes or a no, but clearly something. Treat a new command
            // as abandoning the question rather than ignoring you for the
            // next twelve seconds.
            if text.split(separator: " ").count >= 2 {
                let replacement = text
                pendingToken.isEmpty ? () : dropPending()
                heard = replacement
                lastHeardAt = Date()
                setState(.capturing)
            }

        case .speaking:
            // Only listening for an interruption while it talks.
            if stopWord(in: lower) {
                interrupt()
            }

        case .working:
            break
        }
    }

    /// Finds the wake word, forgivingly. Recognisers routinely drop the
    /// "hey", split a name across words ("hey or bit"), or tack on a plural,
    /// and none of those mean you didn't say it. The range returned is where
    /// the command starts; an empty range at the end means "woken, but I
    /// can't tell where the wake word ended".
    private func wakeRange(in text: String) -> Range<String.Index>? {
        if let r = text.range(of: wakeWord) { return r }
        if let r = text.range(of: wakeKey) { return r }
        if let r = text.range(of: wakeKey + "s") { return r }

        for alias in wakeAliases where !alias.isEmpty {
            if let r = text.range(of: alias) { return r }
        }

        // "hey or bit" - squash the spaces and look again.
        let squashed = text.replacingOccurrences(of: " ", with: "")
        if squashed.contains(wakeKey) || squashed.contains(wakeWord.replacingOccurrences(of: " ", with: "")) {
            return text.endIndex..<text.endIndex
        }

        // Nothing matched literally. A made-up name isn't in the
        // recogniser's vocabulary, so it comes back as the nearest real
        // words it can find - and the nearest real word is usually close.
        // Compare each word, and each pair of adjacent words, against the
        // name and accept anything near enough.
        if fuzzyContainsWake(text) {
            return text.endIndex..<text.endIndex
        }
        return nil
    }

    private func fuzzyContainsWake(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }

        for (index, word) in words.enumerated() {
            if similarity(word, wakeKey) >= wakeThreshold { return true }
            if index + 1 < words.count {
                let pair = word + words[index + 1]
                if similarity(pair, wakeKey) >= wakeThreshold { return true }
            }
        }
        return false
    }

    /// 1.0 is identical, 0 is nothing alike.
    private func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        // A short word can't be a mishearing of a much longer one.
        if abs(a.count - b.count) > max(2, b.count / 2) { return 0 }

        let distance = editDistance(Array(a), Array(b))
        return 1.0 - Double(distance) / Double(max(a.count, b.count))
    }

    private func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,        // deletion
                                 current[j - 1] + 1,     // insertion
                                 previous[j - 1] + cost) // substitution
            }
            previous = current
        }
        return previous[b.count]
    }

    private func yesOrNo(in text: String) -> Bool? {
        let yes = ["yes", "yeah", "yep", "go ahead", "do it", "confirm", "sure", "please do", "send it"]
        let no  = ["no", "nope", "cancel", "stop", "don't", "do not", "never mind", "nevermind", "forget it"]
        for n in no where text.contains(n) { return false }
        for y in yes where text.contains(y) { return true }
        return nil
    }

    /// Words that mean "be quiet", but only when Orbit isn't saying them
    /// itself - it announces "Cancelled." and would otherwise cut itself off.
    private func stopWord(in text: String) -> Bool {
        let stops = ["stop", "shut up", "be quiet", "enough", "cancel that", "never mind"]
        let mine = speakingText.lowercased()
        for word in stops where text.contains(word) && !mine.contains(word) {
            return true
        }
        return false
    }

    private func interrupt() {
        player?.stop()
        player = nil
        speakingText = ""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [orbitPath, "hush"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        status("interrupted", "stopped talking on request")
        setState(.idle)
        restartRecognition()
    }

    /// Drops a pending confirmation without announcing it - used when you
    /// answer a question with a different command instead of yes or no.
    private func dropPending() {
        let token = pendingToken
        pendingToken = ""
        guard !token.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [orbitPath, "cancel", token]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func checkSilence() {
        let quietFor = Date().timeIntervalSince(lastHeardAt)

        if state == .capturing {
            let command = heard.trimmingCharacters(in: .whitespacesAndNewlines)

            if !command.isEmpty, quietFor > commandSilence {
                heard = ""
                greeted = false
                setState(.working)
                plan(command)

            } else if command.isEmpty, !greeted, quietFor > commandSilence {
                // The wake word on its own. Answer it, then keep listening
                // rather than making them say it a second time.
                greeted = true
                greet()

            } else if command.isEmpty, greeted, quietFor > (inConversation ? conversationWindow : followUpWindow) {
                // Nothing followed the greeting. Go quiet without comment -
                // an assistant that announces its own timeout is a nag.
                greeted = false
                inConversation = false
                setState(.idle)
                restartRecognition()
            }
        }

        if state == .confirming, Date().timeIntervalSince(confirmStartedAt) > confirmTimeout {
            cancelPending(silent: true)
        }

        // The one thing worse than a wrong answer is no answer. Any state
        // that isn't "waiting for you" is supposed to be brief; if one of
        // them outlasts its work - a shell command that never returns, a
        // callback that never fires - the ears are dead and nothing says
        // so. Time it out and start listening again.
        let stuckFor = Date().timeIntervalSince(stateSince)
        if (state == .working || state == .speaking), stuckFor > stuckLimit {
            status("recovered", "\(state) lasted \(Int(stuckFor))s; starting over")
            pendingToken = ""
            speakingText = ""
            heard = ""
            greeted = false
            setState(.idle)
            restartRecognition()
        }
    }

    // MARK: - Acting

    private func greet() {
        setState(.working)
        run(["greeting"]) { [weak self] json in
            guard let self = self else { return }
            self.play(json["audio"] as? String ?? "", saying: json["speak"] as? String ?? "") {
                // Straight back to listening, with the follow-up clock
                // starting from the end of the greeting, not the wake word.
                self.heard = ""
                self.lastHeardAt = Date()
                self.setState(.capturing)
                self.restartRecognition()
            }
        }
    }

    /// Where a turn ends up: back in the conversation, or back to waiting
    /// for the wake word.
    private func finishTurn(ended: Bool) {
        greeted = true          // no greeting mid-conversation
        heard = ""
        wakePrefix = ""

        if conversationMode && !ended {
            inConversation = true
            lastHeardAt = Date()
            setState(.capturing)
        } else {
            inConversation = false
            setState(.idle)
        }
        restartRecognition()
    }

    private func plan(_ command: String) {
        // Tells orbit this is a follow-up, so it can stay quiet about
        // things it didn't understand instead of interrupting the room.
        let args = inConversation ? ["plan", "--chat", command] : ["plan", command]
        run(args) { [weak self] json in
            guard let self = self else { return }
            let speak = json["speak"] as? String ?? ""
            let audio = json["audio"] as? String ?? ""
            let confirm = json["confirm"] as? Bool ?? false
            let token = json["token"] as? String ?? ""

            let ended = json["end"] as? Bool ?? false

            self.play(audio, saying: speak) {
                if confirm, !token.isEmpty {
                    self.pendingToken = token
                    self.confirmStartedAt = Date()
                    self.setState(.confirming)
                    self.restartRecognition()
                } else {
                    self.finishTurn(ended: ended)
                }
            }
        }
    }

    private func runPending() {
        let token = pendingToken
        pendingToken = ""
        run(["run", token]) { [weak self] json in
            guard let self = self else { return }
            self.play(json["audio"] as? String ?? "",
                      saying: json["speak"] as? String ?? "Done.") {
                self.finishTurn(ended: false)
            }
        }
    }

    private func cancelPending(silent: Bool = false) {
        let token = pendingToken
        pendingToken = ""
        guard !token.isEmpty else {
            setState(.idle)
            restartRecognition()
            return
        }
        run(["cancel", token]) { [weak self] json in
            guard let self = self else { return }
            let line = silent ? "" : (json["speak"] as? String ?? "Cancelled.")
            self.play(silent ? "" : (json["audio"] as? String ?? ""), saying: line) {
                self.setState(.idle)
                self.restartRecognition()
            }
        }
    }

    // MARK: - Talking to the shell

    private func run(_ arguments: [String], then: @escaping ([String: Any]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.orbitPath] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do { try process.run() } catch {
                NSLog("orbit: \(error.localizedDescription)")
                DispatchQueue.main.async { then(["speak": "Something went wrong running that."]) }
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            // The last line is the JSON; anything before it is log noise.
            let text = String(data: data, encoding: .utf8) ?? ""
            let line = text.split(separator: "\n").last.map(String.init) ?? ""
            let parsed = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]

            DispatchQueue.main.async { then(parsed ?? ["speak": "I couldn't work that one out."]) }
        }
    }

    /// Speaks through orbit (so it uses the same voice as the briefing),
    /// with the microphone closed so it doesn't hear itself.
    /// Plays audio orbit already rendered. Nothing is launched, so this
    /// starts in milliseconds where a shell round trip took a moment.
    private func play(_ path: String, saying text: String, then: @escaping () -> Void) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            say(text, then: then)
            return
        }

        speakingText = text
        setState(.speaking)

        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.volume = 1.0
            player.prepareToPlay()
            self.player = player
            player.play()

            // Poll rather than using the delegate: the interrupt path may
            // stop the player out from under us, and this stays correct
            // either way.
            let duration = player.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) { [weak self] in
                guard let self = self else { return }
                self.speakingText = ""
                self.player = nil
                guard self.state == .speaking else { return }
                then()
            }
        } catch {
            say(text, then: then)
        }
    }

    private func say(_ text: String, then: @escaping () -> Void) {
        guard !text.isEmpty else { then(); return }

        // The microphone stays open while it talks, so "stop" works. Its
        // own words come back through the mic, which is why stopWord()
        // ignores anything Orbit is in the middle of saying.
        speakingText = text
        setState(.speaking)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.orbitPath, "say", text]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async {
                self.speakingText = ""
                // An interruption already moved us on; don't undo it.
                guard self.state == .speaking else { return }
                then()
            }
        }
    }

    /// Keeps the last twenty things heard while idle. If the wake word
    /// never fires, this is the file that says why.
    private func logHeard(_ text: String) {
        guard !heardLogPath.isEmpty, !text.isEmpty else { return }
        if text == lastLogged { return }
        lastLogged = text

        var lines = (try? String(contentsOfFile: heardLogPath, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        lines.append("\(stamp.string(from: Date()))\t\(text)")
        if lines.count > 20 { lines = Array(lines.suffix(20)) }
        try? lines.joined(separator: "\n").write(toFile: heardLogPath, atomically: true, encoding: .utf8)
    }

    private func chime(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func setState(_ next: ListenState) {
        state = next
        stateSince = Date()
        onStateChange?(next)
    }
}
