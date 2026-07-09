import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var state: EditorState
    @State private var root: FileNode
    @State private var text: String = ""
    @State private var dirty = false
    @State private var statusMessage = ""

    @State private var renamingNode: FileNode?
    @State private var renameText: String = ""
    @FocusState private var focusedRenameNode: FileNode?
    @State private var showPreview = false
    @State private var expanded: Set<URL> = []

    init(rootURL: URL, state: EditorState) {
        self.state = state
        _root = State(initialValue: FileNode(url: rootURL, isDirectory: true))
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(flatten(root.children ?? []), id: \.node) { item in
                    row(for: item.node, depth: item.depth)
                        .contentShape(Rectangle())
                        .listRowBackground(state.selectedFile == item.node
                            ? Color.accentColor.opacity(0.22) : Color.clear)
                        .onTapGesture {
                            if item.node.isDirectory { toggleFolder(item.node) }
                            else { state.selectedFile = item.node }
                        }
                        .contextMenu {
                            Button("이름 바꾸기") { beginRename(item.node) }
                            Button("삭제(휴지통으로)", role: .destructive) { delete(item.node) }
                        }
                }
            }
            .navigationTitle(root.name)
            .onKeyPress(.return) {
                guard let sel = state.selectedFile, renamingNode == nil else { return .ignored }
                beginRename(sel)
                return .handled
            }
            .toolbar {
                ToolbarItem {
                    Button("새 파일", systemImage: "doc.badge.plus") { newFile() }
                        .keyboardShortcut("n", modifiers: .command)
                }
                ToolbarItem {
                    Button("폴더 열기", systemImage: "folder.badge.plus") { openFolder() }
                        .keyboardShortcut("o", modifiers: [.command, .shift])
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if showPreview {
                    PreviewView(markdown: text,
                                baseURL: state.selectedFile?.url.deletingLastPathComponent(),
                                onCellEdit: editTableCell)
                } else {
                    MarkdownTextView(text: $text, controller: state.controller)
                        .onChange(of: text) { dirty = true }
                }
                HStack {
                    Text(state.selectedFile?.url.path ?? "왼쪽에서 .md 파일을 선택하세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    Button("저장") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(state.selectedFile == nil || !dirty)
                }
                .padding(8)
            }
            .toolbar {
                ToolbarItemGroup {
                    Group {
                        Button("제목") { state.controller.setHeading(1) }
                        Button("부제목") { state.controller.setHeading(2) }
                        Button("소제목") { state.controller.setHeading(3) }
                        Button("본문") { state.controller.setBody() }
                        Button("글머리", systemImage: "list.bullet") { state.controller.toggleBullet() }
                        Button("굵게", systemImage: "bold") { state.controller.toggleBold() }
                        Button("기울임", systemImage: "italic") { state.controller.toggleItalic() }
                    }
                    .disabled(state.selectedFile == nil || showPreview)
                }
                ToolbarItem {
                    Button(showPreview ? "편집" : "미리보기",
                           systemImage: showPreview ? "pencil" : "eye") {
                        showPreview.toggle()   // 미리보기는 live text 바인딩을 그대로 렌더(저장 불필요)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(state.selectedFile == nil)
                }
            }
        }
        .onChange(of: state.selectedFile) { oldValue, newValue in
            autosave(oldValue)
            load(newValue)
        }
    }

    // 펼쳐진 폴더 목록만 담아 화면에 그릴 행들을 depth와 함께 평탄화 (VS Code식 트리)
    private func flatten(_ nodes: [FileNode], depth: Int = 0) -> [(node: FileNode, depth: Int)] {
        var out: [(FileNode, Int)] = []
        for n in nodes {
            out.append((n, depth))
            if n.isDirectory, expanded.contains(n.url), let ch = n.children {
                out.append(contentsOf: flatten(ch, depth: depth + 1))
            }
        }
        return out
    }

    private func toggleFolder(_ node: FileNode) {
        if expanded.contains(node.url) { expanded.remove(node.url) }
        else { expanded.insert(node.url) }
    }

    @ViewBuilder
    private func row(for node: FileNode, depth: Int) -> some View {
        HStack(spacing: 4) {
            if node.isDirectory {
                Image(systemName: expanded.contains(node.url) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 11)
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
            } else {
                Spacer().frame(width: 11)
                Image(systemName: "doc.text").foregroundStyle(.secondary)
            }
            if renamingNode == node {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .focused($focusedRenameNode, equals: node)
                    .onSubmit { commitRename(node) }
                    .onExitCommand { renamingNode = nil }
            } else {
                Text(node.name)
                    .onTapGesture(count: 2) { beginRename(node) }
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            autosave(state.selectedFile)
            root = FileNode(url: url, isDirectory: true)
            expanded = []
            state.selectedFile = nil
            text = ""
            UserDefaults.standard.set(url.path, forKey: "lastFolder")   // 다음 실행 때 이 폴더로 시작
        }
    }

    private func newFile() {
        let targetDir: URL
        if let sel = state.selectedFile {
            targetDir = sel.isDirectory ? sel.url : sel.url.deletingLastPathComponent()
        } else {
            targetDir = root.url
        }

        guard let name = promptForName(title: "새 마크다운 파일", confirmTitle: "만들기", info: targetDir.path) else { return }
        var fileName = name
        if !fileName.lowercased().hasSuffix(".md") { fileName += ".md" }

        let newURL = targetDir.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            statusMessage = "이미 있는 파일: \(fileName)"
            return
        }
        FileManager.default.createFile(atPath: newURL.path, contents: Data())

        reloadTree()
        state.selectedFile = FileNode(url: newURL, isDirectory: false)
    }

    private func beginRename(_ node: FileNode) {
        renameText = node.name
        renamingNode = node
        focusedRenameNode = node
    }

    private func commitRename(_ node: FileNode) {
        defer { renamingNode = nil }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != node.name else { return }

        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: node.url, to: newURL)
            let wasSelected = state.selectedFile?.url == node.url
            reloadTree()
            if wasSelected {
                state.selectedFile = FileNode(url: newURL, isDirectory: node.isDirectory)
            }
            statusMessage = "이름 변경됨"
        } catch {
            statusMessage = "이름 변경 실패: \(error.localizedDescription)"
        }
    }

    private func delete(_ node: FileNode) {
        let alert = NSAlert()
        alert.messageText = "\"\(node.name)\"을(를) 휴지통으로 옮길까요?"
        alert.addButton(withTitle: "휴지통으로 이동")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            let wasSelected = state.selectedFile?.url == node.url
            reloadTree()
            if wasSelected {
                state.selectedFile = nil
                text = ""
            }
            statusMessage = "휴지통으로 이동함"
        } catch {
            statusMessage = "삭제 실패: \(error.localizedDescription)"
        }
    }

    private func promptForName(title: String, confirmTitle: String, info: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "취소")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "파일이름"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func reloadTree() {
        root = FileNode(url: root.url, isDirectory: true)
    }

    private func load(_ node: FileNode?) {
        guard let node, !node.isDirectory else { return }
        text = (try? String(contentsOf: node.url, encoding: .utf8)) ?? ""
        dirty = false
        statusMessage = ""
    }

    // 미리보기에서 표 칸을 고치면 원문 해당 줄의 칸을 바꿔 반영 + 저장
    private func editTableCell(line: Int, col: Int, value: String) {
        var lines = text.components(separatedBy: "\n")
        guard line < lines.count else { return }
        let updated = Markdown.replacingCell(in: lines[line], col: col, with: value)
        guard updated != lines[line] else { return }
        lines[line] = updated
        text = lines.joined(separator: "\n")
        dirty = true
        save()
    }

    // iOS 메모 앱처럼: 다른 파일로 넘어가기 전에 지금 파일을 조용히 저장
    private func autosave(_ node: FileNode?) {
        guard let node, !node.isDirectory, dirty else { return }
        try? text.write(to: node.url, atomically: true, encoding: .utf8)
        dirty = false
    }

    private func save() {
        guard let node = state.selectedFile else { return }
        do {
            try text.write(to: node.url, atomically: true, encoding: .utf8)
            dirty = false
            statusMessage = "저장됨 \(Date().formatted(date: .omitted, time: .standard))"
        } catch {
            statusMessage = "저장 실패: \(error.localizedDescription)"
        }
    }
}
