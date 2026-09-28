import Foundation
import SwiftData

extension ClipboardItem {
    /// How many of the newest image clips to decode when the hash finds nothing. The
    /// same copy lands on the other device within minutes, so recent clips are enough,
    /// and it keeps the cost to a few small decodes per new image.
    static let imageTwinSearchLimit = 8

    /// A recent image clip showing the same picture as `data`, even when it was saved
    /// in another format (see ImageFingerprint).
    @MainActor
    static func recentImage(matching data: Data, excluding id: UUID? = nil, in context: ModelContext) -> ClipboardItem? {
        guard let target = ImageFingerprint(data: data) else { return nil }
        let image = ContentType.image.rawValue
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentTypeRaw == image },
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = imageTwinSearchLimit + 1
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates
            .filter { $0.id != id }
            .prefix(imageTwinSearchLimit)
            .first { ImageFingerprint(data: $0.rawData).map(target.matches) ?? false }
    }
}
