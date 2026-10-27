import SwiftUI

/// Orbit looks like an instrument: graphite, off-white type, hairline rules,
/// and one colour, the red "on air" light that means it's listening or working.
/// SF Pro Display for headlines, SF Mono for every label, time, and index.
enum Theme {
    // Surfaces
    static let ground = Color(red: 0.043, green: 0.043, blue: 0.047)      // #0B0B0C
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.082)     // #131315
    static let raised = Color(red: 0.102, green: 0.102, blue: 0.114)      // #1A1A1D
    static let rule = Color(red: 0.141, green: 0.141, blue: 0.153)        // #242427
    static let ruleStrong = Color(red: 0.200, green: 0.200, blue: 0.216)  // #333337

    // Ink
    static let ink = Color(red: 0.933, green: 0.925, blue: 0.906)         // #EEECE7
    static let ink2 = Color(red: 0.639, green: 0.631, blue: 0.608)        // #A3A19B
    static let ink3 = Color(red: 0.424, green: 0.420, blue: 0.400)        // #6C6B66

    /// The on-air light. Used only for "live": listening, hearing, working.
    static let signal = Color(red: 1.0, green: 0.290, blue: 0.239)        // #FF4A3D

    // Type
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
    static func numeral(_ size: CGFloat) -> Font { .system(size: size, weight: .light).monospacedDigit() }
    static func body(_ size: CGFloat = 13.5, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Display sizes read best a little tighter than the system default.
    static func tracking(for size: CGFloat) -> CGFloat { -size * 0.025 }
}

// MARK: - Type

/// Uppercase mono, the instrument-panel label used everywhere.
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.ink3
    init(_ text: String, color: Color = Theme.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10.5, weight: .medium))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// A large headline with the tight tracking display type wants.
struct Headline: View {
    let text: String
    var size: CGFloat = 40
    var color: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(Theme.display(size))
            .tracking(Theme.tracking(for: size))
            .foregroundStyle(color)
    }
}

// MARK: - Structure

struct Rule: View {
    var strong = false
    var body: some View { Rectangle().fill(strong ? Theme.ruleStrong : Theme.rule).frame(height: 1) }
}

struct VRule: View {
    var body: some View { Rectangle().fill(Theme.rule).frame(width: 1) }
}

/// "02  Activity ———————" : an index, a label, and a rule to the edge.
struct SectionHeader<Trailing: View>: View {
    let index: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            MonoLabel(index)
            MonoLabel(title, color: Theme.ink2)
            Rule().frame(maxWidth: .infinity)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(index: String, title: String) {
        self.init(index: index, title: title) { EmptyView() }
    }
}

/// The top of every page: a mono kicker, a headline, an optional line under it.
struct PageTitle<Trailing: View>: View {
    let kicker: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel(kicker)
                Headline(text: title, size: 40)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: 520, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension PageTitle where Trailing == EmptyView {
    init(kicker: String, title: String, subtitle: String? = nil) {
        self.init(kicker: kicker, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Scrolling page with Orbit's margins.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 900
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                content
            }
            .padding(.horizontal, 56)
            .padding(.top, 56)
            .padding(.bottom, 56)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Controls

struct InstrumentButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, destructive }
    var kind: Kind = .ghost

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(11, weight: .medium))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(kind == .primary ? Theme.ink : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(kind == .primary ? Color.clear : Theme.ruleStrong, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.ground
        case .ghost: return Theme.ink
        case .destructive: return Theme.signal
        }
    }
}

/// A quiet field: surface fill, hairline border, no glow.
struct InstrumentField: ViewModifier {
    var mono = false
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? Theme.mono(12.5) : Theme.body(13.5))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
    }
}

extension View {
    func instrumentField(mono: Bool = false) -> some View { modifier(InstrumentField(mono: mono)) }
}

// MARK: - The mark and the light

/// Orbit's mark: a thin ring and one body on it. When live, the body is the
/// on-air red and travels the ring; at rest it sits still in off-white.
struct OrbitGlyph: View {
    var live = false
    var lineWidth: CGFloat = 1.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !live)) { timeline in
            let angle = live
                ? timeline.date.timeIntervalSinceReferenceDate * 1.4
                : -0.7
            Canvas { context, size in
                let side = min(size.width, size.height)
                let dot = max(3, side * 0.17)
                let r = (side - dot) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.stroke(ring, with: .color(live ? Theme.ink2 : Theme.ink3), lineWidth: lineWidth)
                let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                context.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)),
                             with: .color(live ? Theme.signal : Theme.ink))
            }
        }
    }
}

/// The on-air tally: a small red light that breathes while live, dark otherwise.
struct Tally: View {
    var live: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { timeline in
            let pulse = live ? 0.55 + 0.45 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)) : 1
            Circle()
                .fill(live ? Theme.signal : Theme.ruleStrong)
                .frame(width: 7, height: 7)
                .opacity(pulse)
                .shadow(color: live ? Theme.signal.opacity(0.6) : .clear, radius: 5)
        }
        .frame(width: 7, height: 7)
    }
}

// MARK: - Formatting

enum Format {
    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// 24-hour clock in mono reads like an instrument log: 09:41.
    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func index(_ n: Int) -> String { String(format: "%02d", n) }
}
