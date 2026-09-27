import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Payload for the system PasteButton. Pasting through the button never shows the
/// "Allow Paste" prompt, so it is the default way to save the current clipboard.
struct PastedClip: Transferable, Sendable {
    let clip: CapturedClip

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .png) { data in
            PastedClip(clip: CapturedClip(kind: .image(data)))
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            PastedClip(clip: CapturedClip(kind: .image(data)))
        }
        DataRepresentation(importedContentType: .heic) { data in
            PastedClip(clip: CapturedClip(kind: .image(data)))
        }
        ProxyRepresentation(importing: { (url: URL) in
            PastedClip(clip: CapturedClip(kind: .url(url)))
        })
        ProxyRepresentation(importing: { (text: String) in
            PastedClip(clip: CapturedClip(kind: .text(text)))
        })
    }
}
