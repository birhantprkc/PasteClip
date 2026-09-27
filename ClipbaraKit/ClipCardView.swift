import SwiftUI

enum ClipCardStyle {
    case grid
    case compact
    case preview
}

/// One clip, rendered the same way in the app grid, previews, and the keyboard.
///
/// Square, borderless card with a one-line header ("Text  2m") and a small type badge
/// in the corner. Images, colors, and code fill the whole card with the header on top.
struct ClipCardView<Clip: ClipPresentable>: View {
    typealias Style = ClipCardStyle

    let item: Clip
    var style: Style = .grid
    var pinboardColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            content
            header
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Layout

    /// Clips whose content fills the card get a light header drawn over it.
    private var isFullBleed: Bool {
        item.contentType == .image || item.contentType == .color || isCode
    }

    private var isCode: Bool {
        item.contentType == .plainText && item.looksLikeCode
    }

    private var padding: CGFloat { style == .compact ? 10 : 14 }
    private var headerHeight: CGFloat { style == .compact ? 30 : 40 }

    private var cornerRadius: CGFloat {
        style == .compact ? ClipStyle.compactCardRadius : ClipStyle.cardRadius
    }

    @ViewBuilder
    private var background: some View {
        if item.contentType == .color {
            ClipStyle.tint(for: .color, colorHex: item.colorHex)
        } else if isCode {
            ClipStyle.codeBackground
        } else {
            colorScheme == .dark ? Color(white: 0.14) : Color.white
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(item.headerTitle)
                .font(style == .compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isFullBleed ? Color.white : Color.primary)
                .lineLimit(1)
            Text(ClipTime.short(item.copiedAt))
                .font(style == .compact ? .caption : .subheadline)
                .foregroundStyle(isFullBleed ? Color.white.opacity(0.75) : Color.secondary)
                .lineLimit(1)
                .fixedSize()  // a long title truncates first; the age always shows
            Spacer(minLength: 4)
            if let pinboardColor {
                Circle()
                    .fill(pinboardColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            typeBadge
        }
        .shadow(color: item.contentType == .image ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
        .padding(.horizontal, padding)
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if item.contentType == .image {
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: headerHeight + 24)
            }
        }
    }

    /// Small rounded icon in the corner, tinted by type. Stands in for the source app
    /// icon, which iOS cannot show for clips copied on another device.
    private var typeBadge: some View {
        let size: CGFloat = style == .compact ? 18 : 22
        return Image(systemName: item.contentType.systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(badgeTint, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    private var badgeTint: Color {
        if isCode { return Color(red: 0.35, green: 0.38, blue: 0.46) }
        if item.contentType == .color { return .black.opacity(0.22) }
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
            if isCode {
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
    }

    /// Lets text run past the card and fades it out, instead of truncating with an ellipsis.
    private func overflowingText(_ text: some View) -> some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                text
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, padding)
                    .padding(.top, headerHeight)
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
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Upper part: a tinted panel with the link glyph (page previews are not fetched).
    /// Lower part: host in bold and the full address.
    private var linkContent: some View {
        VStack(spacing: 0) {
            ZStack {
                ClipStyle.tint(for: .url).opacity(colorScheme == .dark ? 0.28 : 0.12)
                Image(systemName: "globe")
                    .font(.system(size: style == .compact ? 22 : 32, weight: .regular))
                    .foregroundStyle(ClipStyle.tint(for: .url))
                    .padding(.top, headerHeight * 0.6)
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.linkHost ?? item.displayText)
                    .font(style == .compact ? .footnote.weight(.semibold) : .headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(item.displayText)
                    .font(style == .compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(style == .compact ? 1 : 2)
            }
            .padding(.horizontal, padding)
            .padding(.vertical, style == .compact ? 8 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var colorContent: some View {
        Text(item.displayText.uppercased())
            .font(.system(style == .compact ? .callout : .title3, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
        .padding(padding)
        .padding(.top, headerHeight * 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: style == .preview ? 1 : 0.74),
                .init(color: .black.opacity(style == .preview ? 1 : 0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
