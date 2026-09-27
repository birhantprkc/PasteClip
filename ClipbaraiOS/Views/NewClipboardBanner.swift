import SwiftUI

/// Shown when the system clipboard changed since Clipbara last looked. Detecting the
/// change does not read the contents, so no paste prompt appears until the person taps Paste.
struct NewClipboardBanner: View {
    let onPaste: ([CapturedClip]) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("New clipboard content")
                    .font(.subheadline.weight(.semibold))
                Text("Save it to your history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            PasteButton(payloadType: PastedClip.self) { pasted in
                let clips = pasted.map(\.clip)
                Task { @MainActor in onPaste(clips) }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: ClipStyle.cardRadius, style: .continuous))
    }
}
