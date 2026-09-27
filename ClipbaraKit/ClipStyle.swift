import SwiftUI

/// Visual tokens for the iOS surfaces. Header tints match the Mac app's card headers
/// so a clip looks like the same object on both platforms.
enum ClipStyle {
    static let cardRadius: CGFloat = 20
    static let compactCardRadius: CGFloat = 16
    static let gridSpacing: CGFloat = 12
    static let gridPadding: CGFloat = 16

    static func tint(for type: ContentType, colorHex: String? = nil) -> Color {
        switch type {
        case .plainText, .richText, .html, .unknown:
            Color(red: 0.247, green: 0.388, blue: 0.886) // #3F63E2
        case .image:
            Color(red: 0.169, green: 0.231, blue: 0.584) // #2B3B95
        case .url:
            Color(red: 0.0, green: 0.588, blue: 0.533)   // #009688
        case .fileURL:
            Color(red: 0.898, green: 0.494, blue: 0.129) // #E57E21
        case .color:
            colorHex.flatMap(Color.init(clipHex:)) ?? .gray
        }
    }

    static let codeBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let codeForeground = Color(red: 0.86, green: 0.89, blue: 0.95)
}

/// Pinboard colors are derived from the pinboard ID so every device shows the same color
/// without adding a field to the Mac schema.
enum PinboardPalette {
    static let colors: [Color] = [
        Color(red: 0.94, green: 0.30, blue: 0.29), // red
        Color(red: 0.97, green: 0.58, blue: 0.16), // orange
        Color(red: 0.96, green: 0.77, blue: 0.10), // yellow
        Color(red: 0.25, green: 0.73, blue: 0.40), // green
        Color(red: 0.13, green: 0.68, blue: 0.75), // teal
        Color(red: 0.23, green: 0.44, blue: 0.95), // blue
        Color(red: 0.45, green: 0.36, blue: 0.90), // indigo
        Color(red: 0.72, green: 0.36, blue: 0.86), // purple
        Color(red: 0.93, green: 0.36, blue: 0.62), // pink
    ]

    /// Colors follow creation order, so the first nine pinboards never share a color and
    /// every device agrees once pinboards sync.
    static func color(for pinboard: Pinboard, among all: [Pinboard]) -> Color {
        let ordered = all.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let index = ordered.firstIndex { $0.id == pinboard.id } ?? 0
        return colors[index % colors.count]
    }
}

extension Color {
    init?(clipHex: String) {
        let cleaned = clipHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}

enum ClipTime {
    @MainActor private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .hour, .day, .weekOfMonth]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        return f
    }()

    @MainActor private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    /// Compact age such as "now", "5m", "3h", "2d". Older clips show a short date.
    @MainActor
    static func short(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return String(localized: "now") }
        if interval > 60 * 60 * 24 * 28 { return dateFormatter.string(from: date) }
        return formatter.string(from: max(interval, 60)) ?? ""
    }
}
