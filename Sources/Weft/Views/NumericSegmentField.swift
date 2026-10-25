import AppKit
import SwiftUI

/// A native editor inside the custom numeric slots, retaining normal selection and paste commands.
struct NumericSegmentField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    @Binding var focused: Bool
    let maximumDigits: Int
    let maximumValue: Int
    var placeholder = ""
    var fontSize: CGFloat = 14
    var advancesOnSeparator = false
    var onAdvance: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onPaste: (String) -> Bool = { _ in false }
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NumericSegmentHost {
        let host = NumericSegmentHost()
        host.field.delegate = context.coordinator
        return host
    }

    func updateNSView(_ host: NumericSegmentHost, context: Context) {
        context.coordinator.parent = self
        let field = host.field
        field.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        field.textColor = enabled ? .labelColor : .secondaryLabelColor
        field.placeholderString = placeholder
        field.isEnabled = enabled
        field.setAccessibilityLabel(title)
        if field.stringValue != text {
            field.stringValue = text
            field.currentEditor()?.string = text
        }
        if focused && enabled && field.currentEditor() == nil {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, coordinator?.parent.focused == true, field.isEnabled,
                      field.currentEditor() == nil, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumericSegmentField
        init(_ parent: NumericSegmentField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.focused = true }
        func controlTextDidEndEditing(_ notification: Notification) { parent.focused = false }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let entered = field.stringValue
            if parent.onPaste(entered) {
                replaceText(in: field, with: parent.text)
                return
            }

            let digits = String(entered.filter { $0.isASCII && $0.isNumber }.prefix(parent.maximumDigits))
            guard digits.isEmpty || Int(digits).map({ $0 <= parent.maximumValue }) == true else {
                replaceText(in: field, with: parent.text)
                return
            }
            let changed = digits != parent.text
            parent.text = digits
            if entered != digits { replaceText(in: field, with: digits) }
            let separator = parent.advancesOnSeparator && (entered.hasSuffix(".") || entered.hasSuffix(":"))
            if !digits.isEmpty && (separator || (changed && digits.count == parent.maximumDigits)) {
                parent.onAdvance?()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty,
               let backspace = parent.onBackspace {
                backspace()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)), let advance = parent.onAdvance {
                advance()
                return true
            }
            return false
        }

        private func replaceText(in field: NSTextField, with value: String) {
            field.stringValue = value
            if let editor = field.currentEditor() {
                let caret = min(editor.selectedRange.location, value.utf16.count)
                editor.string = value
                editor.selectedRange = NSRange(location: caret, length: 0)
            }
        }
    }
}

final class NumericSegmentHost: NSView {
    let field = NSTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.alignment = .center
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
