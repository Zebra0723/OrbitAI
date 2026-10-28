// Orbit's presence in Galaxy Link, the hub the rest of GalaxyAI meets in.
//
// While this app is running, Orbit is running: it says hello when it
// starts, a heartbeat every thirty seconds after that, and goodbye when it
// quits, so Comet, Nova and the dashboard know whether there is a voice on
// this Mac. Link posts Orbit's introduction in Galaxy Chat on the very
// first hello by itself; nothing here posts anything of its own.
//
// That is all this does. It never asks Link for work, results, chat or
// approvals, and the heartbeat's reply is not even read past its status
// code - so nothing Link does can make Orbit speak. Orbit talks only when
// somebody talks to it.
//
// Everything fails silently and off the main thread. Link not installed,
// not running, or restarting is ordinary, and must never cost the
// microphone a moment.

import Foundation

final class GalaxyPresence {

    /// Serial, so hello, heartbeats and goodbye never overlap or reorder.
    private let queue = DispatchQueue(label: "ai.galaxy.orbit.presence", qos: .utility)
    private let session: URLSession
    private let version: String
    private var timer: DispatchSourceTimer?
    /// False until a hello has landed, and again whenever Link drops out,
    /// so the next tick introduces Orbit afresh instead of beating into
    /// a Link that has forgotten it.
    private var greeted = false

    init(version: String) {
        self.version = version
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    // MARK: - Where Link is

    /// GALAXY_HOME moves it, the same way it moves it for galaxyd.
    private var home: URL {
        let env = ProcessInfo.processInfo.environment["GALAXY_HOME"] ?? ""
        if !env.isEmpty { return URL(fileURLWithPath: env, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Galaxy", isDirectory: true)
    }

    private func read(_ name: String) -> String? {
        guard let text = try? String(contentsOf: home.appendingPathComponent(name), encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Read every time rather than once: Link may be installed, or move
    /// port, while this app is running.
    private func endpoint() -> (base: String, token: String)? {
        guard let token = read("token") else { return nil }
        let port = Int(read("port") ?? "") ?? 7740
        return ("http://127.0.0.1:\(port)", token)
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self = self, self.timer == nil else { return }
            self.hello()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + .seconds(30), repeating: .seconds(30), leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
    }

    /// Called as the app quits. Waits a moment at most for the goodbye to
    /// go out, since the process is about to end; a Link that is slow to
    /// answer just sees Orbit go quiet and marks it stopped by itself.
    func stop() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [weak self] in
            guard let self = self else { done.signal(); return }
            self.timer?.cancel()
            self.timer = nil
            guard self.greeted else { done.signal(); return }
            self.greeted = false
            self.post("/v1/goodbye", [:]) { _ in done.signal() }
        }
        _ = done.wait(timeout: .now() + 1)
    }

    // MARK: - Talking to Link

    private func hello() {
        post("/v1/hello", ["name": "Orbit", "version": version]) { [weak self] status in
            self?.queue.async { self?.greeted = (200..<300).contains(status) }
        }
    }

    private func tick() {
        guard greeted else { hello(); return }
        post("/v1/heartbeat", [:]) { [weak self] status in
            self?.queue.async {
                guard let self = self else { return }
                // 404 is Link saying it has never heard of Orbit (a new
                // database, say): introduce it again. Anything else that
                // is not a 2xx means Link is gone for now.
                if status == 404 {
                    self.hello()
                } else if !(200..<300).contains(status) {
                    self.greeted = false
                }
            }
        }
    }

    /// POSTs a JSON body as Orbit. Hands back the HTTP status, or 0 when
    /// Link could not be reached at all. URLSession sends no Origin and
    /// no Sec-Fetch-Site, which is what tells Link this is a member and
    /// not a web page.
    private func post(_ path: String, _ body: [String: String], _ done: @escaping (Int) -> Void) {
        guard let link = endpoint(), let url = URL(string: link.base + path) else {
            done(0)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        request.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
        request.setValue("orbit", forHTTPHeaderField: "X-Galaxy-Body")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        session.dataTask(with: request) { _, response, _ in
            done((response as? HTTPURLResponse)?.statusCode ?? 0)
        }.resume()
    }
}
