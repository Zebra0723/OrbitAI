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
            window.appearance = NSAppearance(named: .darkAqua) // Orbit is always night
            window.backgroundColor = NSColor(Theme.sky)
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

    var icon: String {
        switch self {
        case .talk: return "waveform"
        case .conversations: return "text.bubble"
        case .memory: return "sparkles.rectangle.stack"
        case .stats: return "chart.bar.xaxis"
        case .macros: return "square.stack.3d.up"
        case .people: return "person.2"
        case .settings: return "slider.horizontal.3"
        }
    }
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
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            ZStack {
                StarField().opacity(0.6)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.skyGradient)
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.starlight)
        .tint(Theme.amber)
        .overlay(alignment: .top) {
            if !OrbitPaths.isInstalled {
                Text("Orbit isn't installed on this Mac yet. Run install.sh in the OrbitAI repo.")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.sky)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.amber, in: Capsule())
                    .padding(.top, 14)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                OrbitMark(active: false)
                    .frame(width: 24, height: 24)
                Text("Orbit")
                    .font(Theme.display(21))
            }
            .padding(.horizontal, 12)
            .padding(.top, 52)
            .padding(.bottom, 26)

            ForEach(AppSection.allCases) { section in
                SidebarRow(section: section, selected: navigation.section == section) {
                    navigation.section = section
                }
            }

            Spacer()

            ListenerBadge(status: store.listener)
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 10)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.amber : Theme.dim)
                Text(section.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(selected ? Theme.starlight : Theme.dim)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.cardHigh : (hovering ? Theme.card : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The microphone's state, at the bottom of the sidebar.
struct ListenerBadge: View {
    let status: ListenerStatus

    private var description: (String, Color) {
        if !status.appRunning { return ("Menu bar app not running", Theme.faint) }
        if status.paused { return ("Microphone off", Theme.faint) }
        switch status.state {
        case "listening", "idle": return ("Listening for \u{201C}\(status.wake.isEmpty ? "hey orbit" : status.wake)\u{201D}", Theme.good)
        case "capturing", "confirming": return ("Hearing you", Theme.amber)
        case "working": return ("Working", Theme.amber)
        case "speaking": return ("Speaking", Theme.ring)
        default: return (status.state.capitalized, Theme.dim)
        }
    }

    var body: some View {
        let info = description
        HStack(spacing: 8) {
            Circle().fill(info.1).frame(width: 7, height: 7)
                .shadow(color: info.1.opacity(0.7), radius: 4)
            Text(info.0)
                .font(Theme.caption(11.5))
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
        }
    }
}

// MARK: - The mark

/// A planet with a tilted ring and a small moon going round it.
struct OrbitMark: View {
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let speed = active ? 1.6 : 0.35
            let angle = t * speed
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let ringW = size * 0.98, ringH = size * 0.36
                // Moon position on the tilted ellipse.
                let mx = cos(angle) * ringW / 2, my = sin(angle) * ringH / 2
                let tilt = -0.42
                let rx = mx * cos(tilt) - my * sin(tilt), ry = mx * sin(tilt) + my * cos(tilt)
                let moonInFront = sin(angle) > 0
                ZStack {
                    if !moonInFront { moon(size).offset(x: rx, y: ry) }
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 1, green: 0.86, blue: 0.62), Theme.amber,
                                                      Color(red: 0.78, green: 0.45, blue: 0.2)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.36))
                        .frame(width: size * 0.5, height: size * 0.5)
                        .shadow(color: Theme.amber.opacity(active ? 0.8 : 0.45), radius: active ? size * 0.3 : size * 0.15)
                    Ellipse()
                        .stroke(Theme.ring.opacity(0.85), lineWidth: max(1, size * 0.045))
                        .frame(width: ringW, height: ringH)
                        .rotationEffect(.radians(tilt))
                    if moonInFront { moon(size).offset(x: rx, y: ry) }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func moon(_ size: CGFloat) -> some View {
        Circle()
            .fill(Theme.starlight)
            .frame(width: size * 0.13, height: size * 0.13)
            .shadow(color: Theme.starlight.opacity(0.8), radius: size * 0.06)
    }
}

/// A faint, fixed field of stars behind every page.
struct StarField: View {
    private struct Star { let x, y, r, a: CGFloat }
    private static let stars: [Star] = {
        var generator = SeededGenerator(seed: 27)
        return (0..<90).map { _ in
            Star(x: .random(in: 0...1, using: &generator), y: .random(in: 0...1, using: &generator),
                 r: .random(in: 0.4...1.3, using: &generator), a: .random(in: 0.15...0.55, using: &generator))
        }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.r * 2, height: star.r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.starlight.opacity(star.a)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic so the stars don't jump around between launches.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
