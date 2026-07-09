import Foundation

// ponytail: 자체 마크다운→HTML 변환기(공통 문법 + GFM 표). 외부 의존성 0, 오프라인.
// 완전한 CommonMark은 아님 — 표·목록·헤더·코드·강조·링크·이미지·인용·수평선까지.
enum Markdown {
    static func toHTML(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        var html = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 코드 블록 ```
            if trimmed.hasPrefix("```") {
                var code = ""
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code += escape(lines[i]) + "\n"
                    i += 1
                }
                i += 1 // 닫는 ```
                html += "<pre><code>\(code)</code></pre>\n"
                continue
            }

            // 표: 현재 줄이 |...| 이고 다음 줄이 구분선이면
            if isTableRow(line), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                let (table, consumed) = parseTable(lines, from: i)
                html += table
                i += consumed
                continue
            }

            // 헤더
            if let m = firstGroups(#"^(#{1,6})\s+(.*)$"#, trimmed) {
                let level = m[1].count
                html += "<h\(level)>\(inline(m[2]))</h\(level)>\n"
                i += 1
                continue
            }

            // 수평선
            if trimmed.range(of: #"^(\-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                html += "<hr>\n"
                i += 1
                continue
            }

            // 인용
            if trimmed.hasPrefix(">") {
                var quote = ""
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    quote += inline(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) + " "
                    i += 1
                }
                html += "<blockquote>\(quote)</blockquote>\n"
                continue
            }

            // 순서 없는 목록
            if trimmed.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
                var items = ""
                while i < lines.count,
                      let m = firstGroups(#"^\s*[-*+]\s+(.*)$"#, lines[i]) {
                    items += "<li>\(inline(m[1]))</li>\n"
                    i += 1
                }
                html += "<ul>\n\(items)</ul>\n"
                continue
            }

            // 순서 있는 목록
            if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                var items = ""
                while i < lines.count,
                      let m = firstGroups(#"^\s*\d+\.\s+(.*)$"#, lines[i]) {
                    items += "<li>\(inline(m[1]))</li>\n"
                    i += 1
                }
                html += "<ol>\n\(items)</ol>\n"
                continue
            }

            // 빈 줄
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 문단 (연속된 일반 줄 묶기)
            var para = ""
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix(">")
                    || t.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil
                    || t.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
                    || (isTableRow(lines[i]) && i + 1 < lines.count && isSeparator(lines[i + 1])) {
                    break
                }
                para += (para.isEmpty ? "" : "<br>") + inline(t)
                i += 1
            }
            if !para.isEmpty { html += "<p>\(para)</p>\n" }
        }
        return html
    }

    // MARK: 표

    private static func isTableRow(_ line: String) -> Bool {
        line.range(of: #"^\s*\|.*\|\s*$"#, options: .regularExpression) != nil
    }
    private static func isSeparator(_ line: String) -> Bool {
        line.range(of: #"^\s*\|[\s:|-]+\|\s*$"#, options: .regularExpression) != nil
    }

    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (String, Int) {
        let header = cells(lines[start])
        let aligns = cells(lines[start + 1]).map { spec -> String in
            let l = spec.hasPrefix(":"), r = spec.hasSuffix(":")
            if l && r { return "center" }
            if r { return "right" }
            if l { return "left" }
            return ""
        }
        func align(_ i: Int) -> String {
            i < aligns.count && !aligns[i].isEmpty ? " style=\"text-align:\(aligns[i])\"" : ""
        }

        var html = "<table>\n<thead><tr>"
        for (idx, h) in header.enumerated() { html += "<th\(align(idx))>\(inline(h))</th>" }
        html += "</tr></thead>\n<tbody>\n"

        var i = start + 2
        while i < lines.count, isTableRow(lines[i]) {
            let row = cells(lines[i])
            html += "<tr>"
            for (idx, c) in row.enumerated() { html += "<td\(align(idx))>\(inline(c))</td>" }
            html += "</tr>\n"
            i += 1
        }
        html += "</tbody>\n</table>\n"
        return (html, i - start)
    }

    // MARK: 인라인

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        s = replace(s, #"!\[([^\]]*)\]\(([^)]+)\)"#, "<img alt=\"$1\" src=\"$2\">")
        s = replace(s, #"\[([^\]]+)\]\(([^)]+)\)"#, "<a href=\"$2\">$1</a>")
        s = replace(s, #"\*\*(.+?)\*\*"#, "<strong>$1</strong>")
        s = replace(s, #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#, "<em>$1</em>")
        s = replace(s, "`([^`\\n]+?)`", "<code>$1</code>")
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: 정규식 헬퍼

    private static func firstGroups(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
