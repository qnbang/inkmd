import AppKit

// ponytail: manipulates the NSTextView directly (select → replace → didChangeText),
// same pattern AppKit itself uses for programmatic edits — keeps undo working for free.
final class EditorController {
    weak var textView: NSTextView?

    func toggleBold() { wrapSelection(with: "**") }
    func toggleItalic() { wrapSelection(with: "*") }

    func setHeading(_ level: Int) {
        setLinePrefix(String(repeating: "#", count: level) + " ")
    }

    func setBody() {
        setLinePrefix("")
    }

    func toggleBullet() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        var line = ns.substring(with: lineRange)
        let hasNewline = line.hasSuffix("\n")
        if hasNewline { line.removeLast() }

        let newLine: String
        if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
        } else {
            newLine = "- " + line
        }
        replaceLine(tv, lineRange: lineRange, with: newLine + (hasNewline ? "\n" : ""))
    }

    private func setLinePrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        var line = ns.substring(with: lineRange)
        let hasNewline = line.hasSuffix("\n")
        if hasNewline { line.removeLast() }

        let stripped = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        let newLine = prefix.isEmpty ? stripped : prefix + stripped
        replaceLine(tv, lineRange: lineRange, with: newLine + (hasNewline ? "\n" : ""))
    }

    private func replaceLine(_ tv: NSTextView, lineRange: NSRange, with replacement: String) {
        guard tv.shouldChangeText(in: lineRange, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: lineRange, with: replacement)
        tv.didChangeText()
    }

    private func wrapSelection(with marker: String) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let ns = tv.string as NSString
        let selected = ns.substring(with: range)
        let replacement = "\(marker)\(selected)\(marker)"
        guard tv.shouldChangeText(in: range, replacementString: replacement) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        let cursor = range.location + (marker as NSString).length + (selected as NSString).length + (marker as NSString).length
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
    }
}
