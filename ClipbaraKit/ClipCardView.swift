import SwiftUI

/// One clip, rendered the same way in the app grid, previews, and the keyboard.
enum ClipCardStyle {
    case grid
    case compact
    case preview
}

struct ClipCardView<Clip: ClipPresentable>: View {
    typealias Style = ClipCardStyle

    let item: Clip
    var style: Style = .grid
    var pinboardColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.headerTitle)
                    .font(style == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(ClipTime.short(item.copiedAt))
                    .font(style == .compact ? .caption2 : .caption)
                    .opacity(0.82)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let pinboardColor {
                Circle()
                    .fill(pinboardColor)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
            Image(systemName: item.contentType.systemImage)
                .font(style == .compact ? .caption2.weight(.semibold) : .footnote.weight(.semibold))
                .frame(width: iconSize, height: iconSize)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: iconSize * 0.3, style: .continuous))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, style == .compact ? 10 : 12)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                headerTint
                // Color clips fill the body with the same color, so darken the header a bit.
                if item.contentType == .color {
                    Color.black.opacity(0.14)
                }
            }
        }
    }

    private var headerTint: Color {
        if item.contentType == .plainText, item.looksLikeCode {
            return Color(red: 0.20, green: 0.22, blue: 0.28)
        }
        return ClipStyle.tint(for: item.contentType, colorHex: item.colorHex)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch item.contentType {
        case .image:
            imageContent
        case .url:
            linkContent
        case .color:
            colorContent
        case .fileURL:
            fileContent
        default:
            if item.looksLikeCode {
                codeContent
            } else {
                textContent
            }
        }
    }

    /// Cards only show the beginning of long clips; laying out the whole text is wasted work.
    private var cardText: String {
        let limit = style == .preview ? 4000 : 700
        let text = item.displayText
        return text.count > limit ? String(text.prefix(limit)) : text
    }

    private var textContent: some View {
        overflowingText(
            Text(cardText)
                .font(style == .compact ? .footnote : (style == .preview ? .body : .callout))
                .foregroundStyle(.primary)
        )
    }

    private var codeContent: some View {
        overflowingText(
            Text(cardText)
                .font(.system(style == .compact ? .caption2 : .caption, design: .monospaced))
                .foregroundStyle(ClipStyle.codeForeground)
        )
        .background(ClipStyle.codeBackground)
    }

    /// Lets text run past the card and fades it out, instead of truncating with an ellipsis.
    private func overflowingText(_ text: some View) -> some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                text
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(style == .compact ? 10 : 12)
            }
            .clipped()
            .mask(fadeMask)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image = item.thumbnailImage() {
            Color.clear
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            placeholder(systemImage: "photo")
        }
    }

    private var linkContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "globe")
                .font(style == .compact ? .title3 : .title2)
                .foregroundStyle(ClipStyle.tint(for: .url))
                .padding(.bottom, 2)
            Text(item.linkHost ?? item.displayText)
                .font(style == .compact ? .footnote.weight(.semibold) : .headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(item.displayText)
                .font(style == .compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(style == .compact ? 2 : 4)
        }
        .padding(style == .compact ? 10 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var colorContent: some View {
        let fill = ClipStyle.tint(for: .color, colorHex: item.colorHex)
        return ZStack {
            fill
            Text(item.displayText.uppercased())
                .font(.system(style == .compact ? .callout : .title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(style == .compact ? 10 : 12)
        }
    }

    private var fileContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.system(size: style == .compact ? 26 : 38))
                .foregroundStyle(ClipStyle.tint(for: .fileURL))
            Text(item.displayText)
                .font(style == .compact ? .caption : .footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: style == .preview ? 1 : 0.72),
                .init(color: .black.opacity(style == .preview ? 1 : 0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Metrics

    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.13) : .white
    }

    private var cornerRadius: CGFloat {
        style == .compact ? ClipStyle.compactCardRadius : ClipStyle.cardRadius
    }

    private var headerHeight: CGFloat {
        style == .compact ? 38 : 48
    }

    private var iconSize: CGFloat {
        style == .compact ? 22 : 28
    }
}
