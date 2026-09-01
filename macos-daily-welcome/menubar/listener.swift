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
}

final class OrbitListener: NSObject {

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var state: ListenState = .idle
    private var heard = ""
    private var lastHeardAt = Date()
    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var pendingToken = ""

    /// Path to the `orbit` script; set by the app delegate.
    var orbitPath: String = ""
    var wakeWord: String = "hey orbit"

    /// Called with the current state so the menu bar icon can reflect it.
    var onStateChange: ((ListenState) -> Void)?

    private let commandSilence: TimeInterval = 1.4
    private let confirmTimeout: TimeInterval = 12
    private var confirmStartedAt = Date()

    /// Seconds to keep listening after answering a bare wake word.
    var followUpWindow: TimeInterval = 9
    /// True once the wake word has been acknowledged on its own, so the
    /// greeting happens at most once per wake rather than on a loop.
    private var greeted = false

    // MARK: - Permissions and lifecycle

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                NSLog("orbit: speech recognition not authorised (\(status.rawValue))")
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    NSLog("orbit: microphone access denied")
                    return
                }
                DispatchQueue.main.async { self?.beginSession() }
            }
        }
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
            NSLog("orbit: audio engine wouldn't start: \(error.localizedDescription)")
            return
        }

        restartRecognition()

        // A recognition task is capped at around a minute, so it gets
        // recycled well before it expires rather than dying mid-sentence.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .idle else { return }
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
        if #available(macOS 13.0, *), recognizer?.supportsOnDeviceRecognition == true {
            req.requiresOnDeviceRecognition = true
        }
        request = req

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.handle(transcript: result.bestTranscription.formattedString)
            }
            if error != nil, self.state == .idle {
                DispatchQueue.main.async { self.restartRecognition() }
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
            guard let range = lower.range(of: wakeWord) else { return }
            // Anything said after the wake word in the same breath counts
            // as the command, so "Hey Orbit, mute" works in one go.
            let tail = String(text[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            heard = tail
            greeted = false
            lastHeardAt = Date()
            setState(.capturing)
            chime("Tink")

        case .capturing:
            heard = text
            lastHeardAt = Date()

        case .confirming:
            if let answer = yesOrNo(in: lower) {
                setState(.working)
                answer ? runPending() : cancelPending()
            }

        case .working:
            break
        }
    }

    private func yesOrNo(in text: String) -> Bool? {
        let yes = ["yes", "yeah", "yep", "go ahead", "do it", "confirm", "sure", "please do", "send it"]
        let no  = ["no", "nope", "cancel", "stop", "don't", "do not", "never mind", "nevermind", "forget it"]
        for n in no where text.contains(n) { return false }
        for y in yes where text.contains(y) { return true }
        return nil
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

            } else if command.isEmpty, greeted, quietFor > followUpWindow {
                // Nothing followed the greeting. Go quiet without comment -
                // an assistant that announces its own timeout is a nag.
                greeted = false
                setState(.idle)
                restartRecognition()
            }
        }

        if state == .confirming, Date().timeIntervalSince(confirmStartedAt) > confirmTimeout {
            cancelPending(silent: true)
        }
    }

    // MARK: - Acting

    private func greet() {
        setState(.working)
        run(["greeting"]) { [weak self] json in
            guard let self = self else { return }
            self.say(json["speak"] as? String ?? "") {
                // Straight back to listening, with the follow-up clock
                // starting from the end of the greeting, not the wake word.
                self.heard = ""
                self.lastHeardAt = Date()
                self.setState(.capturing)
                self.restartRecognition()
            }
        }
    }

    private func plan(_ command: String) {
        run(["plan", command]) { [weak self] json in
            guard let self = self else { return }
            let speak = json["speak"] as? String ?? ""
            let confirm = json["confirm"] as? Bool ?? false
            let token = json["token"] as? String ?? ""

            self.say(speak) {
                if confirm, !token.isEmpty {
                    self.pendingToken = token
                    self.confirmStartedAt = Date()
                    self.setState(.confirming)
                    self.restartRecognition()
                } else {
                    self.setState(.idle)
                    self.restartRecognition()
                }
            }
        }
    }

    private func runPending() {
        let token = pendingToken
        pendingToken = ""
        run(["run", token]) { [weak self] json in
            guard let self = self else { return }
            self.say(json["speak"] as? String ?? "Done.") {
                self.setState(.idle)
                self.restartRecognition()
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
            self.say(line) {
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
    private func say(_ text: String, then: @escaping () -> Void) {
        guard !text.isEmpty else { then(); return }

        endRecognition()
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.orbitPath, "say", text]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async { then() }
        }
    }

    private func chime(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func setState(_ next: ListenState) {
        state = next
        onStateChange?(next)
    }
}
