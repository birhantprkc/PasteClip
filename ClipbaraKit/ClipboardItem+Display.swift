import Foundation
import UIKit

extension ClipboardItem {
    /// Text used for search, previews, and plain-text copies.
    var displayText: String {
        if let textContent, !textContent.isEmpty { return textContent }
        switch contentType {
        case .plainText, .url, .color, .fileURL:
            return String(data: rawData, encoding: .utf8) ?? ""
        default:
            return ""
        }
    }

    var headerTitle: String {
        ClipHeuristics.headerTitle(userTitle: userTitle, type: contentType, text: displayText)
    }

    var linkURL: URL? {
        guard contentType == .url else { return nil }
        let text = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    var linkHost: String? {
        contentType == .url ? ClipHeuristics.host(of: displayText) : nil
    }

    var colorHex: String? {
        contentType == .color ? displayText : nil
    }

    var canCopyAsPlainText: Bool {
        contentType == .richText || contentType == .html
    }

    /// A light heuristic, only used to switch the card to a monospaced dark style.
    var looksLikeCode: Bool {
        ClipHeuristics.looksLikeCode(displayText, type: contentType)
    }

    func thumbnailImage() -> UIImage? {
        if let thumbnailData, let image = UIImage(data: thumbnailData) { return image }
        guard contentType == .image else { return nil }
        return UIImage(data: rawData)
    }

    func fullImage() -> UIImage? {
        guard contentType == .image else { return nil }
        return UIImage(data: rawData) ?? thumbnailData.flatMap(UIImage.init(data:))
    }

    /// Short footer describing the content, e.g. "124 characters" or "1200 × 800".
    var detailSummary: String {
        switch contentType {
        case .image:
            if let image = fullImage() {
                let w = Int(image.size.width * image.scale)
                let h = Int(image.size.height * image.scale)
                return "\(w) × \(h)"
            }
            return contentType.displayName
        case .url:
            return linkHost ?? displayText
        case .color:
            return displayText
        default:
            let count = displayText.count
            return String(localized: "\(count) characters")
        }
    }
}
