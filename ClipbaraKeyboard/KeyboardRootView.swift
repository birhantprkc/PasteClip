import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class KeyboardModel {
    var snapshot: KeyboardSnapshot = .empty
    var selectedBoardID: UUID?
    var showsNextKeyboardKey = true
    var returnKeyType: UIReturnKeyType = .default
    var lastInsertedID: UUID?

    @ObservationIgnored var insert: (String) -> Void = { _ in }
    @ObservationIgnored var deleteBackward: () -> Void = {}
    @ObservationIgnored var nextKeyboard: () -> Void = {}

    var clips: [KeyboardSnapshot.Clip] {
        snapshot.clips(in: selectedBoardID)
    }

    func reload() {
        snapshot = KeyboardSnapshot.load()
        if let selectedBoardID, !snapshot.boards.contains(where: { $0.id == selectedBoardID }) {
            self.selectedBoardID = nil
        }
    }

    func tap(_ clip: KeyboardSnapshot.Clip) {
        insert(clip.text)
        lastInsertedID = clip.id
    }
}

struct KeyboardRootView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            boardBar
            cards
            keyRow
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: model.lastInsertedID)
    }

    // MARK: - Pinboard switcher

    private var boardBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                boardChip(title: String(localized: "Clipboard"), color: nil, id: nil)
                ForEach(model.snapshot.boards) { board in
                    boardChip(title: board.name, color: PinboardPalette.color(at: board.colorIndex), id: board.id)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 32)
    }

    private func boardChip(title: String, color: Color?, id: UUID?) -> some View {
        let isOn = model.selectedBoardID == id
        return Button {
            withAnimation(.snappy(duration: 0.2)) { model.selectedBoardID = id }
        } label: {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                } else {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.footnote.weight(isOn ? .semibold : .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .background(isOn ? KeyStyle.keyFill : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Cards

    @ViewBuilder
    private var cards: some View {
        let clips = model.clips
        if clips.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: model.selectedBoardID == nil ? "clipboard" : "pin")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(model.selectedBoardID == nil
                     ? "Open Clipbara and save a clip to see it here."
                     : "No clips on this pinboard yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(clips) { clip in
                        Button {
                            model.tap(clip)
                        } label: {
                            ClipCardView(item: clip, style: .compact)
                                .frame(width: 150)
                        }
                        .buttonStyle(CardPressStyle())
                        .accessibilityLabel(Text("\(clip.headerTitle), \(clip.text)"))
                        .accessibilityHint(Text("Types this clip"))
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxHeight: .infinity)
            .id(model.selectedBoardID)
        }
    }

    // MARK: - Keys

    private var keyRow: some View {
        HStack(spacing: 6) {
            if model.showsNextKeyboardKey {
                KeyButton(systemImage: "globe", isSpecial: true, width: 44, label: "Next Keyboard") {
                    model.nextKeyboard()
                }
            }
            KeyButton(title: String(localized: "space"), isSpecial: false, width: nil, label: "Space") {
                model.insert(" ")
            }
            RepeatingKeyButton(systemImage: "delete.left", label: "Delete") {
                model.deleteBackward()
            }
            KeyButton(systemImage: "return.left", isSpecial: true, width: 64, label: "Return") {
                model.insert("\n")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
    }
}

// MARK: - Key styling

enum KeyStyle {
    static let keyFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    static let specialFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(white: 0.70, alpha: 1)
    })
}

private struct KeyButton: View {
    var title: String? = nil
    var systemImage: String? = nil
    let isSpecial: Bool
    let width: CGFloat?
    let label: LocalizedStringKey
    let action: () -> Void

    init(title: String, isSpecial: Bool, width: CGFloat?, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.isSpecial = isSpecial
        self.width = width
        self.label = label
        self.action = action
    }

    init(systemImage: String, isSpecial: Bool, width: CGFloat?, label: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.isSpecial = isSpecial
        self.width = width
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .regular))
                } else if let title {
                    Text(title).font(.system(size: 16))
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
            .frame(width: width)
            .background(isSpecial ? KeyStyle.specialFill : KeyStyle.keyFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Delete key: one tap deletes one character; holding it keeps deleting.
private struct RepeatingKeyButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .foregroundStyle(.primary)
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .background(isPressed ? KeyStyle.keyFill : KeyStyle.specialFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .milliseconds(90))
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
