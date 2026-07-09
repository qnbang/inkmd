import SwiftUI
import WebKit

// ponytail: 미리보기 전용 WKWebView. 편집은 텍스트뷰가, 렌더(진짜 표·이미지)는 여기가 담당.
struct PreviewView: NSViewRepresentable {
    var markdown: String
    var baseURL: URL?      // 상대 경로 이미지(png 등) 로드용 — 파일이 있는 폴더

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")   // 시스템 배경 투과
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        web.loadHTMLString(Self.page(Markdown.toHTML(markdown)), baseURL: baseURL)
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
        a { color: #2f7bd6; }
        </style></head><body>\(body)</body></html>
        """
    }
}
