import SwiftUI
import WebKit

// ponytail: 미리보기 전용 WKWebView. 편집은 텍스트뷰가, 렌더(진짜 표·이미지)는 여기가 담당.
// 표 칸은 contenteditable → 고치면 onCellEdit로 원문 줄·칸 위치를 되돌려줌.
struct PreviewView: NSViewRepresentable {
    var markdown: String
    var baseURL: URL?                                  // 상대 경로 이미지(png 등) 로드용
    var onCellEdit: (_ line: Int, _ col: Int, _ text: String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCellEdit: onCellEdit) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "cellEdit")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        // 같은 내용이면 다시 안 그림(우리가 유발한 편집 후 깜빡임 방지)
        guard context.coordinator.lastMarkdown != markdown else { return }
        context.coordinator.lastMarkdown = markdown
        web.loadHTMLString(Self.renderedPage(markdown, baseURL: baseURL), baseURL: baseURL)
    }

    // 마크다운 → HTML + 로컬 이미지는 data URI로 인라인(WKWebView가 문자열 HTML서 로컬파일 못 읽는 제약 우회)
    static func renderedPage(_ markdown: String, baseURL: URL?) -> String {
        page(inlineLocalImages(Markdown.toHTML(markdown), baseURL: baseURL))
    }

    static func inlineLocalImages(_ html: String, baseURL: URL?) -> String {
        guard let baseURL,
              let re = try? NSRegularExpression(pattern: #"<img alt="([^"]*)" src="([^"]+)">"#) else { return html }
        let ns = html as NSString
        var result = html
        // 뒤에서부터 치환(오프셋 안 깨지게)
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let src = ns.substring(with: m.range(at: 2))
            if src.hasPrefix("http") || src.hasPrefix("data:") { continue }
            let fileURL = URL(fileURLWithPath: src, relativeTo: baseURL)
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let mime = Self.mime(for: fileURL.pathExtension)
            let alt = ns.substring(with: m.range(at: 1))
            let dataURI = "<img alt=\"\(alt)\" src=\"data:\(mime);base64,\(data.base64EncodedString())\">"
            result = (result as NSString).replacingCharacters(in: m.range, with: dataURI)
        }
        return result
    }

    private static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onCellEdit: (Int, Int, String) -> Void
        var lastMarkdown: String?
        init(onCellEdit: @escaping (Int, Int, String) -> Void) { self.onCellEdit = onCellEdit }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any],
                  let line = d["line"] as? Int, let col = d["col"] as? Int,
                  let text = d["text"] as? String else { return }
            onCellEdit(line, col, text)
        }
    }

    static func page(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px -apple-system, sans-serif; line-height: 1.6; margin: 24px; color: #1a1a1a; }
        @media (prefers-color-scheme: dark) { body { color: #e8e8e8; } }
        h1,h2,h3 { line-height: 1.3; }
        code { background: rgba(128,128,128,.18); padding: 2px 5px; border-radius: 4px; font-size: .9em; }
        pre { background: rgba(128,128,128,.14); padding: 12px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid rgba(128,128,128,.4); margin: 0; padding: 2px 14px; color: #888; }
        img { max-width: 100%; }
        table { border-collapse: collapse; margin: 12px 0; }
        th, td { border: 1px solid rgba(128,128,128,.4); padding: 7px 12px; }
        th { background: rgba(128,128,128,.12); }
        td:focus, th:focus { outline: 2px solid #2f7bd6; outline-offset: -2px; }
        a { color: #2f7bd6; }
        </style></head><body>\(body)
        <script>
        document.querySelectorAll('td,th').forEach(function(c){
          c.addEventListener('keydown', function(e){ if(e.key==='Enter'){ e.preventDefault(); c.blur(); }});
          c.addEventListener('blur', function(){
            window.webkit.messageHandlers.cellEdit.postMessage({
              line: parseInt(c.dataset.line), col: parseInt(c.dataset.col), text: c.innerText
            });
          });
        });
        </script></body></html>
        """
    }
}
