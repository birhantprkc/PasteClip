import Foundation

/// `clipbara://` links, so launchers such as Raycast or Alfred can open the
/// panel with their own shortcuts (#7).
///
///     clipbara://open     opens the history panel
///     clipbara://toggle   opens it, or closes it if it is open
///     clipbara://queue    starts or ends the Clip Queue
enum URLCommand: String, CaseIterable {
    case open
    case toggle
    case queue

    init?(url: URL) {
        guard url.scheme?.lowercased() == "clipbara" else { return nil }
        // Accept both clipbara://open and clipbara:open.
        // URL.path is empty for clipbara:open on some macOS versions (CI), so
        // read the path from URLComponents.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""
        let path = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let name = host.isEmpty ? path : host
        self.init(rawValue: name.lowercased())
    }
}
