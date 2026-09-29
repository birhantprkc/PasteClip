import AppKit
import SwiftUI

/// Plain text editor for a clip's content in the preview (#54). Styled like
/// `SelectableTextView` so switching to edit mode doesn't move the text.
struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    var isMonospaced: Bool = false
    var fontSize: CGFloat = 14
    var lineSpacing: CGFloat = 5
    var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = contentInsets

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFindBar = true
        textView.usesFontPanel = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // The preview is always dark.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let font: NSFont = isMonospaced
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.92, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        textView.typingAttributes = attributes
        textView.insertionPointColor = .white
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        textView.delegate = context.coordinator

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        scrollView.contentInsets = contentInsets
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
