import SwiftUI
import AppKit

struct ClipboardQuickLookView: View {
    let item: ClipboardItem
    let shelfHeight: CGFloat
    let onClose: () -> Void
    let onPaste: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var cachedImage: NSImage?
    @State private var imageMetadata: (width: Int, height: Int)?
    @State private var showActualSize = false
    @State private var cachedCharCount: Int = 0
    @State private var cachedIsCodeLike: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(colorScheme == .dark ? 0.26 : 0.16)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)

                quickLookBubble(in: geo.size)
                    .padding(.bottom, shelfHeight + 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }
        }
        .task(id: item.id) {
            if item.contentType == .image {
                let image = NSImage(data: item.rawData)
                cachedImage = image
                if let rep = image?.representations.first {
                    imageMetadata = (rep.pixelsWide, rep.pixelsHigh)
                }
                cachedCharCount = 0
                cachedIsCodeLike = false
            } else {
                cachedImage = nil
                imageMetadata = nil
                showActualSize = false

                let text = item.textContent ?? ""
                cachedCharCount = text.count
                let sample = text.prefix(2000)
                let codeKeywords = ["func ", "var ", "let ", "class ", "struct ", "import ", "def ", "return ", "if ", "for ", "{", "}"]
                cachedIsCodeLike = codeKeywords.contains { sample.contains($0) }
            }
        }
    }

    private func quickLookBubble(in size: CGSize) -> some View {
        let maxBubbleWidth = min(size.width * 0.72, 1080)
        let availableHeight = max(size.height - shelfHeight - 68, 360)
        let bubbleHeight = min(max(availableHeight * 0.86, 360), 720)

        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider().opacity(0.35)
                content
                Divider().opacity(0.35)
                footer
            }
            .frame(width: maxBubbleWidth, height: bubbleHeight)
            .background(.regularMaterial)
            .background(bubbleTint)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.22), radius: 28, y: 10)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            BubblePointer()
                .fill(bubblePointerFill)
                .frame(width: 32, height: 14)
                .overlay(
                    BubblePointer()
                        .stroke(borderColor, lineWidth: 0.75)
                )
                .offset(y: -1)
        }
        .environment(\.colorScheme, .dark)
        .onTapGesture { }
    }

    private var toolbar: some View {
        let tint = DesignTokens.typeTint(for: item.contentType, itemColor: item.textContent)

        return HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Close")

            HStack(spacing: 6) {
                Image(systemName: item.contentType.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(item.userTitle ?? item.contentType.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)

            if let appName = item.sourceAppName {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(appName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.contentType == .image {
                Button {
                    showActualSize.toggle()
                } label: {
                    Image(systemName: showActualSize ? "arrow.down.right.and.arrow.up.left" : "1.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(toolbarButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(showActualSize ? "Fit" : "Actual Size")
            }

            if let bundleId = item.sourceAppBundleId {
                Image(nsImage: AppIconProvider.icon(for: bundleId, size: 24))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }

            Button(action: onPaste) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                    Text("Paste")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.accentColor.opacity(0.13))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    @ViewBuilder
    private var content: some View {
        switch item.contentType {
        case .plainText, .richText, .html, .unknown:
            textContent
        case .image:
            imageContent
        case .url:
            urlContent
        case .fileURL:
            fileContent
        case .color:
            colorContent
        }
    }

    private var textContent: some View {
        SelectableTextView(
            text: item.textContent ?? "...",
            isMonospaced: cachedIsCodeLike,
            fontSize: 14,
            lineSpacing: 5
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(contentBackground)
    }

    private var imageContent: some View {
        ZStack {
            checkerboardBackground

            if let cachedImage {
                ScrollView([.horizontal, .vertical], showsIndicators: showActualSize) {
                    Image(nsImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: showActualSize ? actualWidth(for: cachedImage) : nil,
                            height: showActualSize ? actualHeight(for: cachedImage) : nil
                        )
                        .frame(maxWidth: showActualSize ? nil : .infinity, maxHeight: showActualSize ? nil : .infinity)
                        .padding(showActualSize ? 24 : 18)
                }
            } else {
                placeholder(systemImage: "photo", text: "Unable to load image")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var urlContent: some View {
        let urlString = item.textContent ?? ""
        let url = URL(string: urlString)
        let domain = url?.host ?? urlString

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                iconTile(systemImage: "globe", tint: .teal)

                VStack(alignment: .leading, spacing: 5) {
                    Text(domain)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(urlString)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(contentBackground)
    }

    private var fileContent: some View {
        let fileIcon: NSImage = {
            if let urlString = String(data: item.rawData, encoding: .utf8),
               let url = URL(string: urlString) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSWorkspace.shared.icon(for: .data)
        }()
        let fileName = item.textContent?.components(separatedBy: "/").last ?? "File"

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                        .frame(width: 64, height: 64)
                    Image(nsImage: fileIcon)
                        .resizable()
                        .frame(width: 46, height: 46)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(fileName)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(2)

                    Text(item.textContent ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(contentBackground)
    }

    private var colorContent: some View {
        let color = Color(hex: item.textContent ?? "") ?? .gray

        return VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(item.textContent ?? "Color")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(contentBackground)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(primaryMetadata)

            Text("·")
                .foregroundStyle(.quaternary)

            Text(RelativeTimeFormatter.string(for: item.copiedAt))

            Spacer()

            Text(item.contentType.displayName)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private func placeholder(systemImage: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    private func iconTile(systemImage: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 64, height: 64)
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(tint)
        }
    }

    private var checkerboardBackground: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 10
            let rows = Int(ceil(size.height / cellSize))
            let cols = Int(ceil(size.width / cellSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight
                            ? Color(white: colorScheme == .dark ? 0.21 : 0.78)
                            : Color(white: colorScheme == .dark ? 0.16 : 0.70))
                    )
                }
            }
        }
    }

    private var primaryMetadata: String {
        switch item.contentType {
        case .plainText, .richText, .html, .unknown:
            return "\(cachedCharCount) chars"
        case .image:
            if let imageMetadata {
                return "\(imageMetadata.width) x \(imageMetadata.height) · \(fileSizeText)"
            }
            return fileSizeText
        case .url:
            return "URL"
        case .fileURL:
            return "File"
        case .color:
            return item.textContent ?? "Color"
        }
    }

    private var fileSizeText: String {
        let kb = item.rawData.count / 1024
        if kb >= 1024 {
            return "\(String(format: "%.1f", Double(kb) / 1024))MB"
        }
        return "\(kb)KB"
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.10)
    }

    private var toolbarButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.08)
    }

    private var contentBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.08) : Color.black.opacity(0.18)
    }

    private var bubbleTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.06) : Color.black.opacity(0.24)
    }

    private var bubblePointerFill: Color {
        colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.30)
    }

    private func actualWidth(for image: NSImage) -> CGFloat {
        min(max(image.size.width, 120), 1600)
    }

    private func actualHeight(for image: NSImage) -> CGFloat {
        min(max(image.size.height, 120), 1200)
    }
}

private struct BubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
