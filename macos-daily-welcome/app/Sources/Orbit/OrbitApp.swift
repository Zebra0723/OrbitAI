import AppKit
import SwiftUI

@main
enum OrbitMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let store = OrbitStore()
    private let navigation = Navigation()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Orbit"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua) // Orbit is always graphite
            window.backgroundColor = NSColor(Theme.ground)
            window.minSize = NSSize(width: 920, height: 600)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: RootView(store: store, navigation: navigation)
                    .environment(\.colorScheme, .dark)
            )
            window.center()
            window.setFrameAutosaveName("OrbitWindow")
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Orbit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Orbit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Orbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Orbit")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let goMenu = NSMenu(title: "Go")
        for (index, section) in AppSection.allCases.enumerated() {
            let item = goMenu.addItem(withTitle: section.title, action: #selector(go(_:)), keyEquivalent: "\(index + 1)")
            item.target = self
            item.tag = index
        }
        main.addItem(submenu: goMenu, title: "Go")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu
        return main
    }

    @objc private func openSettings() {
        navigation.section = .settings
        showWindow()
    }

    @objc private func go(_ sender: NSMenuItem) {
        guard AppSection.allCases.indices.contains(sender.tag) else { return }
        navigation.section = AppSection.allCases[sender.tag]
        showWindow()
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

// MARK: - Navigation

enum AppSection: String, CaseIterable, Identifiable {
    case talk, conversations, memory, stats, macros, people, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .talk: return "Talk"
        case .conversations: return "Conversations"
        case .memory: return "Memory"
        case .stats: return "Stats"
        case .macros: return "Macros"
        case .people: return "People"
        case .settings: return "Settings"
        }
    }

    var number: String { Format.index((AppSection.allCases.firstIndex(of: self) ?? 0) + 1) }
}

@MainActor
final class Navigation: ObservableObject {
    @Published var section: AppSection = .talk
}

struct RootView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var navigation: Navigation

    var body: some View {
        HStack(spacing: 0) {
            rail
            VRule()
            Group {
                switch navigation.section {
                case .talk: TalkView(store: store)
                case .conversations: ConversationsView(store: store)
                case .memory: MemoryView(store: store)
                case .stats: StatsView(store: store)
                case .macros: ConfEditor(kind: .macros, store: store)
                case .people: ConfEditor(kind: .people, store: store)
                case .settings: SettingsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground)
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                OrbitGlyph(live: store.listener.isLive)
                    .frame(width: 18, height: 18)
                Text("Orbit")
                    .font(Theme.display(17))
                    .tracking(-0.3)
            }
            .padding(.top, 56)
            .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    RailItem(section: section, selected: navigation.section == section) {
                        navigation.section = section
                    }
                }
            }

            Spacer()

            if !OrbitPaths.isInstalled {
                Text("Orbit isn't installed on this Mac. Run install.sh in the OrbitAI repo.")
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.ink2)
                    .padding(.bottom, 18)
            }

            Rule()
            StatusLine(status: store.listener)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .frame(width: 216)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.ground)
    }
}

private struct RailItem: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(section.number)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(selected ? Theme.ink2 : Theme.ink3)
                Text(section.title)
                    .font(Theme.body(13.5, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected || hovering ? Theme.ink : Theme.ink2)
                Spacer()
            }
            .frame(height: 30)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: 2, height: 14)
                    .offset(x: -24)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension ListenerStatus {
    /// Hearing, thinking, or speaking right now.
    var isLive: Bool { appRunning && !paused && ["capturing", "confirming", "working", "speaking"].contains(state) }

    var line: String {
        if !appRunning { return "Menu bar app off" }
        if paused { return "Microphone off" }
        switch state {
        case "listening", "idle": return "Waiting for \u{201C}\(wake.isEmpty ? "hey orbit" : wake)\u{201D}"
        case "capturing", "confirming": return "On air"
        case "working": return "Working"
        case "speaking": return "Speaking"
        default: return state.capitalized
        }
    }
}

/// The tally and one line of state, at the foot of the rail.
struct StatusLine: View {
    let status: ListenerStatus

    var body: some View {
        HStack(spacing: 10) {
            Tally(live: status.isLive)
            Text(status.line.uppercased())
                .font(Theme.mono(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(status.isLive ? Theme.ink : Theme.ink3)
                .lineLimit(2)
        }
    }
}
