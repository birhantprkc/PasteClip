import Observation
import SwiftUI

enum ClipCollection: Hashable {
    case history
    case pinboard(UUID)
}

enum FilterToken: Identifiable, Hashable {
    case kind(ClipKind)
    case source(String)

    var id: String {
        switch self {
        case .kind(let kind): "kind:\(kind.rawValue)"
        case .source(let name): "source:\(name)"
        }
    }

    var title: String {
        switch self {
        case .kind(let kind): kind.title
        case .source(let name): name
        }
    }

    var systemImage: String {
        switch self {
        case .kind(let kind): kind.systemImage
        case .source: "app"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .kind(let kind): kind.matches(item)
        case .source(let name): item.sourceAppName == name
        }
    }
}

/// Filter groups shown as search tokens. Rich text and HTML count as text.
enum ClipKind: String, CaseIterable {
    case text, link, image, color, file

    var title: String {
        switch self {
        case .text: String(localized: "Text")
        case .link: String(localized: "Link")
        case .image: String(localized: "Image")
        case .color: String(localized: "Color")
        case .file: String(localized: "File")
        }
    }

    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .link: "link"
        case .image: "photo"
        case .color: "paintpalette"
        case .file: "doc"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .text: [.plainText, .richText, .html, .unknown].contains(item.contentType)
        case .link: item.contentType == .url
        case .image: item.contentType == .image
        case .color: item.contentType == .color
        case .file: item.contentType == .fileURL
        }
    }
}

/// Screen-level UI state that card context menus need to reach (sheets, alerts, toasts).
@MainActor
@Observable
final class ClipsUIState {
    var collection: ClipCollection = .history
    var isSelecting = false
    var selectedIDs: Set<UUID> = []

    var previewItem: ClipboardItem?
    var renameItem: ClipboardItem?
    var renameText = ""
    var newPinboardItems: [ClipboardItem] = []
    var isNamingNewPinboard = false
    var newPinboardName = ""

    var toast: Toast?
    private var toastTask: Task<Void, Never>?

    struct Toast: Equatable {
        let id = UUID()
        let message: String
        let systemImage: String
    }

    func show(_ message: String, systemImage: String = "checkmark.circle.fill") {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.3)) {
            toast = Toast(message: message, systemImage: systemImage)
        }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self?.toast = nil
            }
        }
    }

    func beginSelecting(with item: ClipboardItem? = nil) {
        withAnimation(.snappy) {
            isSelecting = true
            selectedIDs = item.map { [$0.id] } ?? []
        }
    }

    func endSelecting() {
        withAnimation(.snappy) {
            isSelecting = false
            selectedIDs = []
        }
    }

    func toggleSelection(_ item: ClipboardItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func beginRename(_ item: ClipboardItem) {
        renameText = item.userTitle ?? ""
        renameItem = item
    }

    func beginNewPinboard(for items: [ClipboardItem]) {
        newPinboardItems = items
        newPinboardName = ""
        isNamingNewPinboard = true
    }
}
