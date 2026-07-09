import AppKit
import SwiftUI

// ponytail: raw SwiftPM executables aren't launched via LaunchServices, so
// NSApplication never gets told to become a regular foreground app on its own.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 숨은 검증 모드: --snapshot <출력.png> 로 실행하면 실제 앱의 하이라이팅으로 렌더한 이미지를 저장하고 종료
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
           i + 1 < CommandLine.arguments.count {
            Self.renderSnapshot(to: CommandLine.arguments[i + 1])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    static func renderSnapshot(to path: String) {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.string = "1. 사과\n2. 배\n- 포도\n일반 문장입니다\n# 제목입니다"
        // 앱과 똑같은 Coordinator로 하이라이팅
        let view = MarkdownTextView(text: .constant(tv.string), controller: EditorController())
        view.makeCoordinator().applyHighlighting(tv.textStorage!)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        guard let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { return }
        tv.cacheDisplay(in: tv.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

@main
struct MDEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var editorState = EditorState()

    var body: some Scene {
        WindowGroup {
            ContentView(
                rootURL: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents/claude-workspace"),
                state: editorState
            )
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandMenu("서식") {
                Group {
                    Button("제목") { editorState.controller.setHeading(1) }
                        .keyboardShortcut("1", modifiers: .command)
                    Button("부제목") { editorState.controller.setHeading(2) }
                        .keyboardShortcut("2", modifiers: .command)
                    Button("소제목") { editorState.controller.setHeading(3) }
                        .keyboardShortcut("3", modifiers: .command)
                    Button("본문") { editorState.controller.setBody() }
                        .keyboardShortcut("0", modifiers: .command)
                    Divider()
                    Button("글머리 기호") { editorState.controller.toggleBullet() }
                        .keyboardShortcut("8", modifiers: [.command, .shift])
                    Divider()
                    Button("굵게") { editorState.controller.toggleBold() }
                        .keyboardShortcut("b", modifiers: .command)
                    Button("기울임") { editorState.controller.toggleItalic() }
                        .keyboardShortcut("i", modifiers: .command)
                }
                .disabled(editorState.selectedFile == nil)
            }
        }
    }
}
