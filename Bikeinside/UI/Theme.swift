import BikeinsideCore
import SwiftUI

enum Theme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.10)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let panelHighlight = Color(red: 0.16, green: 0.18, blue: 0.24)
    static let accent = Color(red: 1.0, green: 0.56, blue: 0.18)
    static let accentSecondary = Color(red: 0.25, green: 0.70, blue: 1.0)
    static let textSecondary = Color.white.opacity(0.62)
    static let good = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let warn = Color(red: 1.0, green: 0.78, blue: 0.20)
    static let bad = Color(red: 1.0, green: 0.35, blue: 0.35)
    static let heart = Color(red: 1.0, green: 0.30, blue: 0.40)

    static func zoneColor(_ zone: PowerZone) -> Color {
        switch zone {
        case .z1: return Color(white: 0.62)
        case .z2: return Color(red: 0.20, green: 0.55, blue: 1.0)
        case .z3: return Color(red: 0.25, green: 0.80, blue: 0.40)
        case .z4: return Color(red: 1.0, green: 0.82, blue: 0.15)
        case .z5: return Color(red: 1.0, green: 0.50, blue: 0.12)
        case .z6: return Color(red: 0.95, green: 0.22, blue: 0.22)
        case .z7: return Color(red: 0.68, green: 0.30, blue: 0.95)
        }
    }

    static func zoneColor(power: Double, ftp: Double) -> Color {
        zoneColor(PowerZone.zone(power: power, ftp: ftp))
    }

    static func jersey(_ index: Int) -> Color {
        let c = RiderProfile.jerseyPalette[min(max(index, 0), RiderProfile.jerseyPalette.count - 1)]
        return Color(red: c.x, green: c.y, blue: c.z)
    }

    static func gradeColor(_ grade: Double) -> Color {
        switch grade {
        case ..<(-0.02): return accentSecondary
        case ..<0.02: return .white
        case ..<0.05: return warn
        case ..<0.08: return accent
        default: return bad
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func km(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func number(_ v: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func percent(_ grade: Double) -> String {
        number(grade * 100, decimals: 1) + " %"
    }

    static func date(_ d: Date) -> String {
        d.formatted(.dateTime.locale(Locale(identifier: "sv_SE")).weekday(.wide).day().month(.wide).hour().minute())
    }

    static func gap(_ seconds: Double) -> String {
        let s = abs(seconds)
        let sign = seconds >= 0 ? "+" : "−"
        return s < 60 ? "\(sign)\(Int(s.rounded())) s" : "\(sign)\(duration(s))"
    }
}

/// Rounded dark card used throughout the menus.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.06)))
    }
}

/// Big primary call-to-action button.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
    }
}

/// Small label/value pair.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
