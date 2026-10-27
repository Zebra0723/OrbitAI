import SwiftUI

/// Orbit's look: a night sky. Deep navy surfaces, starlight text, a warm
/// planet-amber accent, SF Pro Rounded for display type and small tracked
/// capitals for labels. Always dark.
enum Theme {
    static let sky = Color(red: 0.039, green: 0.047, blue: 0.098)        // #0A0C19
    static let skyHigh = Color(red: 0.067, green: 0.075, blue: 0.157)    // #111328
    static let sidebar = Color(red: 0.055, green: 0.063, blue: 0.129)    // #0E1021
    static let card = Color(red: 0.086, green: 0.098, blue: 0.208)       // #161935
    static let cardHigh = Color(red: 0.118, green: 0.133, blue: 0.267)   // #1E2244
    static let hairline = Color(red: 0.165, green: 0.180, blue: 0.333)   // #2A2E55

    static let starlight = Color(red: 0.925, green: 0.918, blue: 0.965)  // #ECEAF6
    static let dim = Color(red: 0.616, green: 0.627, blue: 0.776)        // #9DA0C6
    static let faint = Color(red: 0.420, green: 0.431, blue: 0.592)      // #6B6E97

    /// The planet. Buttons, the mark, highlights.
    static let amber = Color(red: 0.941, green: 0.702, blue: 0.369)      // #F0B35E
    /// Data marks on charts: amber stepped into the dark-mode lightness band.
    static let amberData = Color(red: 0.769, green: 0.518, blue: 0.227)  // #C4843A
    /// The ring. Secondary highlights.
    static let ring = Color(red: 0.541, green: 0.576, blue: 1.0)         // #8A93FF
    static let danger = Color(red: 1.0, green: 0.478, blue: 0.431)       // #FF7A6E
    static let good = Color(red: 0.420, green: 0.851, blue: 0.651)       // #6BD9A6

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func title(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    static func body(_ size: CGFloat = 13.5) -> Font { .system(size: size) }
    static func caption(_ size: CGFloat = 11.5) -> Font { .system(size: size, weight: .medium) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, design: .monospaced) }
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }

    static let skyGradient = LinearGradient(colors: [skyHigh, sky], startPoint: .top, endPoint: .bottom)
}

// MARK: - Shared pieces

/// Small tracked capitals above a section.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Theme.faint)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.starlight)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

struct OrbitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .primary ? Color.clear : Theme.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.sky
        case .secondary: return Theme.starlight
        case .destructive: return Theme.danger
        }
    }

    private var background: Color { kind == .primary ? Theme.amber : Theme.cardHigh }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Theme.body())
            .foregroundStyle(Theme.starlight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.sky.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

extension View {
    func orbitField() -> some View { modifier(FieldStyle()) }
}

/// Page scaffolding shared by the scrolling pages.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 860
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .padding(.horizontal, 40)
            .padding(.top, 46)
            .padding(.bottom, 40)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

enum Format {
    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
