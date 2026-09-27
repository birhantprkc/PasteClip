import SwiftUI

/// Filter chips above the grid while searching. Selected chips also appear as tokens
/// inside the search field, so they can be removed from either place.
struct FilterChipsRow: View {
    let available: [FilterToken]
    @Binding var tokens: [FilterToken]

    @Environment(\.isSearching) private var isSearching

    var body: some View {
        if (isSearching || !tokens.isEmpty) && !available.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(available) { token in
                        chip(token)
                    }
                }
                .padding(.horizontal, ClipStyle.gridPadding)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -ClipStyle.gridPadding)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func chip(_ token: FilterToken) -> some View {
        let isOn = tokens.contains(token)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isOn {
                    tokens.removeAll { $0 == token }
                } else {
                    tokens.append(token)
                }
            }
        } label: {
            Label(token.title, systemImage: token.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("filterChip-\(token.id)")
    }
}
