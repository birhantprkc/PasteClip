import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Save to Clipbara" in the share sheet. Shared items go to the inbox; the app imports
/// them the next time it becomes active.
final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareConfirmationView(state: state))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        Task { @MainActor in
            let saved = await Self.save(providers)
            state.phase = saved > 0 ? .saved(saved) : .failed
            try? await Task.sleep(for: .seconds(saved > 0 ? 0.9 : 1.6))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @MainActor
    private static func save(_ providers: [NSItemProvider]) async -> Int {
        var saved = 0
        for provider in providers {
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let data = try await loadData(provider, type: .image) {
                    try ShareInbox.add(imageData: data)
                    saved += 1
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = try await loadURL(provider) {
                    try ShareInbox.add(url: url)
                    saved += 1
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try await loadText(provider) {
                    try ShareInbox.add(text: text)
                    saved += 1
                }
            } catch {
                continue
            }
        }
        return saved
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data) }
            }
        }
    }

    private static func loadURL(_ provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: url) }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: text) }
            }
        }
    }
}

@MainActor
@Observable
final class ShareState {
    enum Phase: Equatable {
        case saving
        case saved(Int)
        case failed
    }

    var phase: Phase = .saving
}

struct ShareConfirmationView: View {
    let state: ShareState

    var body: some View {
        VStack(spacing: 12) {
            switch state.phase {
            case .saving:
                ProgressView()
                    .controlSize(.large)
                Text("Saving…")
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: state.phase)
                Text("Saved to Clipbara")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Nothing to save")
            }
        }
        .font(.headline)
        .padding(28)
        .frame(minWidth: 200)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.15))
    }
}
