import SwiftUI
import UIKit

@MainActor
final class ComposeEditorHandle: ObservableObject {
    weak var view: UITextView?

    func finishComposition() -> (text: String, selection: NSRange)? {
        guard let view, view.markedTextRange != nil else { return nil }
        view.unmarkText()
        return (view.text, view.selectedRange)
    }
}

struct ComposeTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var focused: Bool
    var fontSize: CGFloat
    var tint: Color
    var textArt = false
    var handle: ComposeEditorHandle? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.accessibilityLabel = textArt ? "颜文字内容" : "正文"
        handle?.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        let font: UIFont = textArt ? .monospacedSystemFont(ofSize: fontSize, weight: .regular) : .systemFont(ofSize: fontSize)
        if view.font != font { view.font = font }
        if textArt {
            view.autocorrectionType = .no
            view.spellCheckingType = .no
            view.autocapitalizationType = .none
            view.smartQuotesType = .no
            view.smartDashesType = .no
            view.smartInsertDeleteType = .no
        }
        view.textColor = UIColor(XDTheme.text)
        view.tintColor = UIColor(tint)
        view.isEditable = context.environment.isEnabled
        // Do not replace marked text while an input method is composing it.
        if view.markedTextRange == nil {
            if view.text != text { view.text = text }
            let count = (view.text as NSString).length
            let start = min(selection.location, count)
            let range = NSRange(location: start, length: min(selection.length, count - start))
            if view.selectedRange != range {
                view.selectedRange = range
                if view.isFirstResponder { view.scrollRangeToVisible(range) }
            }
        }
        if focused && !view.isFirstResponder {
            if view.window != nil { view.becomeFirstResponder() }
        } else if !focused && view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposeTextEditor
        var updating = false

        init(_ parent: ComposeTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            parent.text = textView.text
            parent.selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else { return }
            parent.selection = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !updating { parent.focused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if !updating { parent.focused = false }
        }
    }
}
