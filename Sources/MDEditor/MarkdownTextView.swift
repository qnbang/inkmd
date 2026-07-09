import AppKit
import SwiftUI

private let baseSize: CGFloat = 14

// ponytail: regex-based line/inline highlighting, not a real markdown parser —
// good enough for headers/bold/italic/code, upgrade to a proper parser if it starts lying.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var controller: EditorController

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.font = .systemFont(ofSize: baseSize)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true            // ⌘Z 실행취소 / ⇧⌘Z 다시실행
        textView.usesFindBar = true           // ⌘F 찾기
        textView.isIncrementalSearchingEnabled = true
        textView.string = text
        context.coordinator.applyHighlighting(textView.textStorage!)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = controller.textView else { return }
        guard textView.string != text else { return }
        textView.string = text
        context.coordinator.applyHighlighting(textView.textStorage!)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        // 표준 제목 크기 배율 (HTML h1~h6 관례 기반, 본문 14pt 기준)
        // h1 2.0×=28 · h2 1.5×=21 · h3 1.25×=17.5 · h4 1.0×=14 · h5·h6 소폭 축소
        static func headingSize(_ level: Int) -> CGFloat {
            switch level {
            case 1: return baseSize * 2.0    // 제목
            case 2: return baseSize * 1.5    // 부제목
            case 3: return baseSize * 1.25   // 소제목
            case 4: return baseSize * 1.1
            case 5: return baseSize
            default: return baseSize * 0.9
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting(textView.textStorage!)
        }

        // 엔터를 가로채 리스트 자동 이어쓰기 (아이폰 메모 방식)
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return continueList(textView)
            }
            return false
        }

        // "1" 뒤 스페이스 → "1. "로 자동 변환 (아이폰 메모식: 숫자만 치고 띄어도 번호 리스트 시작)
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard replacementString == " " else { return true }
            let ns = textView.string as NSString
            let lineStart = ns.lineRange(for: NSRange(location: affectedCharRange.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: affectedCharRange.location - lineStart))
            guard before.range(of: #"^\s*\d+$"#, options: .regularExpression) != nil else { return true }

            // 기본 스페이스는 막고, 대신 ". "를 넣어 "1. " 마커 완성
            DispatchQueue.main.async {
                guard textView.shouldChangeText(in: affectedCharRange, replacementString: ". ") else { return }
                textView.textStorage?.replaceCharacters(in: affectedCharRange, with: ". ")
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 2, length: 0))
            }
            return false
        }

        private func continueList(_ tv: NSTextView) -> Bool {
            let ns = tv.string as NSString
            let caret = tv.selectedRange().location
            let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }

            // 글머리표: "- ", "* ", "+ "
            if let g = firstMatch(#"^(\s*)([-*+])(\s+)(.*)$"#, in: line) {
                let indent = g[1], bullet = g[2], space = g[3], content = g[4]
                if content.isEmpty {
                    exitList(tv, lineRange: lineRange, markerLength: (indent + bullet + space).count)
                } else {
                    insertText(tv, "\n\(indent)\(bullet) ")
                }
                return true
            }

            // 번호 매기기: "1. ", "2. " …
            if let g = firstMatch(#"^(\s*)(\d+)\.(\s+)(.*)$"#, in: line) {
                let indent = g[1], numberStr = g[2], space = g[3], content = g[4]
                if content.isEmpty {
                    exitList(tv, lineRange: lineRange, markerLength: (indent + numberStr + "." + space).count)
                } else {
                    let next = (Int(numberStr) ?? 1) + 1
                    insertText(tv, "\n\(indent)\(next). ")
                }
                return true
            }

            return false  // 리스트가 아니면 기본 줄바꿈
        }

        // 빈 항목에서 엔터 → 마커만 지우고 리스트 빠져나가기
        private func exitList(_ tv: NSTextView, lineRange: NSRange, markerLength: Int) {
            let markerRange = NSRange(location: lineRange.location, length: markerLength)
            guard tv.shouldChangeText(in: markerRange, replacementString: "") else { return }
            tv.textStorage?.replaceCharacters(in: markerRange, with: "")
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        }

        private func insertText(_ tv: NSTextView, _ s: String) {
            let r = tv.selectedRange()
            guard tv.shouldChangeText(in: r, replacementString: s) else { return }
            tv.textStorage?.replaceCharacters(in: r, with: s)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: r.location + (s as NSString).length, length: 0))
        }

        private func firstMatch(_ pattern: String, in text: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let ns = text as NSString
            guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }

        func applyHighlighting(_ storage: NSTextStorage) {
            let full = storage.string as NSString
            let fullRange = NSRange(location: 0, length: full.length)

            storage.beginEditing()
            storage.setAttributes([
                .font: NSFont.systemFont(ofSize: baseSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: NSParagraphStyle.default   // 이전 패스의 리스트 들여쓰기 초기화
            ], range: fullRange)

            // 헤더: "#### " 마커는 숨기고, 본문은 표준 제목 크기로
            withGroups(storage, in: full, pattern: #"^(#{1,6}[ \t]+)(.*)$"#, options: [.anchorsMatchLines]) { marker, content in
                hide(storage, marker)
                let hashes = full.substring(with: marker).prefix(while: { $0 == "#" }).count
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: Self.headingSize(hashes)), range: content)
            }

            // 글머리표 "- "는 리스트 표시라 남겨두되 살짝 연하게 (원문은 그대로 저장)
            highlight(storage, in: full, pattern: #"^\s*[-*+]\s"#, options: [.anchorsMatchLines]) { range in
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }

            // 리스트 줄(글머리표·번호) 들여쓰기 — 항목 전체가 살짝 들어가고, 줄이 넘어가면 글이 마커 뒤에 정렬 (아이폰 메모 방식)
            highlight(storage, in: full, pattern: #"^(\s*)([-*+]|\d+\.)\s"#, options: [.anchorsMatchLines]) { markerRange in
                let lineRange = full.lineRange(for: markerRange)
                let markerWidth = (full.substring(with: markerRange) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: baseSize)]).width
                let base: CGFloat = 36                    // 탭 한 칸만큼 항목 전체를 통째로 들여쓰기
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = base          // 첫 줄(마커 포함)도 들여쓰기 → 짧은 항목도 바로 티남
                style.headIndent = base + markerWidth      // 넘친 줄은 마커 너비만큼 더
                storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
            }

            // 굵게: **텍스트** (마커 숨김은 withMarkedGroup이 담당)
            withMarkedGroup(storage, in: full, pattern: #"\*\*(.+?)\*\*"#) { content in
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: baseSize), range: content)
            }

            // 기울임: *텍스트* (굵게용 ** 는 건너뜀)
            withMarkedGroup(storage, in: full, pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#) { content in
                let italic = NSFontManager.shared.convert(.systemFont(ofSize: baseSize), toHaveTrait: .italicFontMask)
                storage.addAttribute(.font, value: italic, range: content)
            }

            // 인라인 코드: `텍스트`
            withMarkedGroup(storage, in: full, pattern: "`([^`\\n]+?)`") { content in
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular), range: content)
                storage.addAttribute(.backgroundColor, value: NSColor.systemGray.withAlphaComponent(0.18), range: content)
            }

            // 표: `|`로 이뤄진 줄은 고정폭 글꼴로 → 칸이 세로로 정렬돼 표처럼 읽힘
            highlight(storage, in: full, pattern: #"^\s*\|.*\|\s*$"#, options: [.anchorsMatchLines]) { range in
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular), range: range)
            }
            // 표 구분선(|---|:--:|)은 문법 표시라 흐리게
            highlight(storage, in: full, pattern: #"^\s*\|[\s:|-]+\|\s*$"#, options: [.anchorsMatchLines]) { range in
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            }

            storage.endEditing()
        }

        // ponytail: 마커는 텍스트에 그대로 남아있음(저장 시 원본 그대로), 화면에서만 크기 0으로 접어 숨김.
        // 그 위치에 커서를 놓고 지우는 건 여전히 가능하지만 눈에 안 보여 약간 어색할 수 있음.
        private func hide(_ storage: NSTextStorage, _ range: NSRange) {
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        }

        private func highlight(_ storage: NSTextStorage, in full: NSString, pattern: String, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: full as String, range: NSRange(location: 0, length: full.length))
            for match in matches {
                apply(match.range)
            }
        }

        /// pattern에 그룹 2개(마커, 본문)가 있는 경우 — 예: 헤더 "(#{1,6} )(내용)"
        private func withGroups(_ storage: NSTextStorage, in full: NSString, pattern: String, options: NSRegularExpression.Options = [], apply: (NSRange, NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: full as String, range: NSRange(location: 0, length: full.length))
            for match in matches where match.numberOfRanges >= 3 {
                apply(match.range(at: 1), match.range(at: 2))
            }
        }

        /// pattern이 "마커+본문+마커" 형태(예: **본문**)인 경우 — 그룹1(본문) 앞뒤를 마커로 보고 자동으로 숨김 처리
        private func withMarkedGroup(_ storage: NSTextStorage, in full: NSString, pattern: String, options: NSRegularExpression.Options = [], apply: (NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let matches = regex.matches(in: full as String, range: NSRange(location: 0, length: full.length))
            for match in matches where match.numberOfRanges >= 2 {
                let whole = match.range(at: 0)
                let content = match.range(at: 1)
                let prefix = NSRange(location: whole.location, length: content.location - whole.location)
                let suffixStart = content.location + content.length
                let suffix = NSRange(location: suffixStart, length: whole.location + whole.length - suffixStart)
                if prefix.length > 0 { hide(storage, prefix) }
                if suffix.length > 0 { hide(storage, suffix) }
                apply(content)
            }
        }
    }
}
