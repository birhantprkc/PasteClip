import Foundation
import UIKit

/// What a card needs to draw a clip. Implemented by the SwiftData model in the app and
/// by the lightweight snapshot the keyboard reads.
protocol ClipPresentable {
    var contentType: ContentType { get }
    var copiedAt: Date { get }
    var displayText: String { get }
    var headerTitle: String { get }
    var linkHost: String? { get }
    var colorHex: String? { get }
    var looksLikeCode: Bool { get }
    func thumbnailImage() -> UIImage?
}

extension ClipboardItem: ClipPresentable {}

enum ClipHeuristics {
    static func looksLikeCode(_ text: String, type: ContentType) -> Bool {
        guard type == .plainText || type == .unknown else { return false }
        guard text.contains("\n") else { return false }
        let signals = ["{", "}", ";", "=>", "->", "func ", "const ", "let ", "import ", "def ", "return ", "</", "#include", "SELECT ", "class "]
        let hits = signals.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return hits >= 3
    }

    static func host(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = URL(string: trimmed)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func headerTitle(userTitle: String?, type: ContentType, text: String) -> String {
        if let userTitle, !userTitle.isEmpty { return userTitle }
        if type == .plainText, looksLikeCode(text, type: type) { return String(localized: "Code") }
        return type.displayName
    }
}
