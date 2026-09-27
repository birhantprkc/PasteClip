#if DEBUG
import SwiftData
import UIKit

/// Sample clips for Simulator screenshots and UI checks. Only loaded with the
/// `-ClipbaraDemoData` launch argument, into an in-memory store.
@MainActor
enum DemoData {
    static func seed(into context: ModelContext) {
        let library = ClipLibrary(context: context)
        let now = Date()

        func add(_ clip: CapturedClip, minutesAgo: Double, title: String? = nil, source: String? = nil) -> ClipboardItem? {
            guard let item = library.save(clip) else { return nil }
            item.copiedAt = now.addingTimeInterval(-minutesAgo * 60)
            item.userTitle = title
            item.sourceAppName = source
            return item
        }

        let swatch = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 420)).image { ctx in
            let colors = [UIColor(red: 0.36, green: 0.58, blue: 0.98, alpha: 1).cgColor,
                          UIColor(red: 0.11, green: 0.24, blue: 0.59, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 420), options: [])
            UIColor.white.withAlphaComponent(0.9).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 380, y: 60, width: 120, height: 120))
        }

        let email = add(.init(kind: .text("Hi Jamie,\n\nThanks for the quick call today. I've attached the revised timeline and the notes from the design review. Let me know if Thursday still works for the handoff.")), minutesAgo: 2, source: "Mail")
        let link = add(.init(kind: .url(URL(string: "https://developer.apple.com/documentation/cloudkit/cksyncengine")!)), minutesAgo: 9, source: "Safari")
        let code = add(.init(kind: .text("func greet(_ name: String) -> String {\n    let trimmed = name.trimmingCharacters(in: .whitespaces)\n    return \"Hello, \\(trimmed)!\";\n}")), minutesAgo: 34, source: "Xcode")
        _ = add(.init(kind: .image(swatch.pngData()!)), minutesAgo: 70, source: "Photos")
        let address = add(.init(kind: .text("1 Infinite Loop, Cupertino, CA 95014")), minutesAgo: 180, title: "Office address", source: "Maps")
        _ = add(.init(kind: .text("Meeting moved to 3:30 PM. Room B-204.")), minutesAgo: 60 * 26, source: "Messages")
        let reply = add(.init(kind: .text("Thanks for reaching out! I'm away until Monday and will reply as soon as I'm back.")), minutesAgo: 60 * 50, title: "Out of office", source: "Notes")
        _ = add(.init(kind: .url(URL(string: "https://github.com/mobrava/Clipbara")!)), minutesAgo: 60 * 75, source: "Safari")

        let colorItem = ClipboardItem(contentType: .color, rawData: Data("#2563EB".utf8), textContent: "#2563EB", sourceAppName: "Figma", contentHash: "demo-color")
        colorItem.copiedAt = now.addingTimeInterval(-60 * 60 * 5)
        context.insert(colorItem)

        let links = library.createPinboard(named: "Useful Links", existing: [])
        let notes = library.createPinboard(named: "Important Notes", existing: [links])
        let templates = library.createPinboard(named: "Email Templates", existing: [links, notes])
        let snippets = library.createPinboard(named: "Code Snippets", existing: [links, notes, templates])

        if let link { library.add([link], to: links) }
        if let address { library.add([address], to: notes) }
        library.add([email, reply].compactMap { $0 }, to: templates)
        if let code { library.add([code], to: snippets) }
        try? context.save()
    }
}
#endif
