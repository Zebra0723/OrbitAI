// Is anybody else using the microphone right now?
//
// "On the phone" is not one app. A relayed iPhone call is FaceTime, but a
// call is just as likely to be Zoom, Meet in a browser tab, Teams,
// Discord, WhatsApp or a Slack huddle - and a list of app names would be
// out of date the week it was written.
//
// So the question asked here is the one that actually matters: is some
// process other than this one recording from the microphone. CoreAudio
// answers it directly from macOS 14.4 on, which covers every call app
// there is and everything that hasn't been written yet.

import Foundation
import Darwin
import CoreAudio
import AppKit

enum CallWatch {

    /// Bundle identifiers that should never count as being on a call, on
    /// top of our own process. Set from config.
    static var ignoredBundleIDs: Set<String> = []

    /// The name of whatever else is holding the microphone, or nil when
    /// the microphone is ours alone. `nil` is the normal answer.
    static func appUsingMicrophone() -> String? {
        if #available(macOS 14.4, *) {
            return modernCheck()
        }
        return legacyCheck()
    }

    // MARK: - macOS 14.4 and later

    @available(macOS 14.4, *)
    private static func modernCheck() -> String? {
        let mine = ProcessInfo.processInfo.processIdentifier
        for process in audioProcesses() {
            guard isRunningInput(process) else { continue }
            let pid = processPID(process)
            guard pid > 0, pid != mine else { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            if let bundle = app?.bundleIdentifier, ignoredBundleIDs.contains(bundle) { continue }
            // Our own helpers, if the app ever grows any.
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier { continue }

            return app?.localizedName ?? app?.bundleIdentifier ?? processName(pid) ?? "another app"
        }
        return nil
    }

    @available(macOS 14.4, *)
    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    @available(macOS 14.4, *)
    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    @available(macOS 14.4, *)
    private static func processPID(_ process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr else { return -1 }
        return pid
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return (String(cString: buffer) as NSString).lastPathComponent
    }

    // MARK: - Before macOS 14.4

    /// No per-process audio API here, so this falls back to asking whether
    /// a known call app is running. Less exact - a launched Zoom is not a
    /// Zoom call - which is why the accurate path above is preferred.
    private static let callBundleIDs: Set<String> = [
        "com.apple.FaceTime", "us.zoom.xos", "com.microsoft.teams",
        "com.microsoft.teams2", "com.cisco.webexmeetingsapp", "com.hnc.Discord",
        "com.skype.skype", "net.whatsapp.WhatsApp", "com.tinyspeck.slackmacgap",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
    ]

    private static func legacyCheck() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier else { continue }
            if ignoredBundleIDs.contains(bundle) { continue }
            if callBundleIDs.contains(bundle) { return app.localizedName ?? bundle }
        }
        return nil
    }
}
