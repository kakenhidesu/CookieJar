import SwiftUI
import UIKit

/// Native selection stays independent of the single tap that toggles a hidden segment.
struct SelectableSpoilerText: UIViewRepresentable {
    let text: AttributedString
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let revealedHiddenSegments: Set<Int>
    let onToggleHidden: (Int) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let segmentKey = NSAttributedString.Key(XDContent.HiddenSegmentAttribute.name)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.linkTextAttributes = [:]
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleHidden(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let previous = context.coordinator.parent
        let visibilityChanged = previous.revealedHiddenSegments != revealedHiddenSegments
            && previous.fontSize == fontSize && previous.lineSpacing == lineSpacing
        context.coordinator.parent = self
        let attributedText = makeAttributedText()
        let previousText = view.attributedText ?? NSAttributedString(string: "")
        guard !previousText.isEqual(to: attributedText) else { return }
        let selection = view.selectedRange
        let sameText = previousText.string == attributedText.string
        let applyText = {
            view.attributedText = attributedText
            if sameText, selection.location != NSNotFound,
               NSMaxRange(selection) <= attributedText.length {
                view.selectedRange = selection
            } else {
                view.selectedRange = NSRange(location: 0, length: 0)
            }
            view.invalidateIntrinsicContentSize()
            view.layoutIfNeeded()
        }
        // Only fade a user-triggered reveal/hide, not initial rendering or font changes.
        if visibilityChanged && sameText && view.window != nil && selection.length == 0 && !reduceMotion {
            view.layoutIfNeeded()
            UIView.transition(with: view, duration: 0.18,
                              options: [.transitionCrossDissolve, .curveEaseInOut,
                                        .allowUserInteraction, .beginFromCurrentState],
                              animations: applyText)
        } else {
            applyText()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    private func makeAttributedText() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let baseFont = UIFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing

        for run in text.runs {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
            if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.traitItalic) }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
            var attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(descriptor: descriptor, size: fontSize),
                .foregroundColor: UIColor(run.swiftUI.foregroundColor ?? XDTheme.text),
                .paragraphStyle: paragraphStyle
            ]
            if let color = run.swiftUI.backgroundColor { attributes[.backgroundColor] = UIColor(color) }
            if run.swiftUI.strikethroughStyle != nil { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.swiftUI.underlineStyle != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            if let segment = run[XDContent.HiddenSegmentAttribute.self] { attributes[Self.segmentKey] = segment }
            result.append(NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableSpoilerText

        init(_ parent: SelectableSpoilerText) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view as? UITextView,
                  view.selectedRange.length == 0 else { return false }
            return hiddenSegment(at: touch.location(in: view), in: view) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            // Let selection, dragging and scrolling finish without toggling the text.
            if other is UILongPressGestureRecognizer || other is UIPanGestureRecognizer { return true }
            return (other as? UITapGestureRecognizer).map { $0.numberOfTapsRequired > 1 } ?? false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // UITextView also uses a single tap to manage its selection.
            (other as? UITapGestureRecognizer).map { $0.numberOfTapsRequired == 1 } ?? false
        }

        @objc func toggleHidden(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? UITextView,
                  view.selectedRange.length == 0,
                  let segment = hiddenSegment(at: gesture.location(in: view), in: view) else { return }
            parent.onToggleHidden(segment)
        }

        private func hiddenSegment(at point: CGPoint, in view: UITextView) -> Int? {
            let point = CGPoint(x: point.x - view.textContainerInset.left,
                                y: point.y - view.textContainerInset.top)
            let layout = view.layoutManager
            layout.ensureLayout(for: view.textContainer)
            let glyph = layout.glyphIndex(for: point, in: view.textContainer)
            guard glyph < layout.numberOfGlyphs,
                  layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                      in: view.textContainer).contains(point) else { return nil }
            let index = layout.characterIndexForGlyph(at: glyph)
            guard index < view.textStorage.length,
                  view.textStorage.attribute(.link, at: index, effectiveRange: nil) == nil else { return nil }
            return view.textStorage.attribute(SelectableSpoilerText.segmentKey,
                                              at: index, effectiveRange: nil) as? Int
        }

        func textView(_ textView: UITextView, shouldInteractWith URL: URL,
                      in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            guard interaction == .invokeDefaultAction else { return true }
            parent.openURL(URL)
            return false
        }
    }
}
