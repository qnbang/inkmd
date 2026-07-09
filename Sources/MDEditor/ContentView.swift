import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var state: EditorState
    @State private var roots: [FileNode]         // 사이드바 최상위 폴더들 (VS Code 다중 폴더)
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
        // 저장된 폴더 목록이 있으면 복원, 없으면 시작 폴더 하나
        let saved = (UserDefaults.standard.stringArray(forKey: "folders") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let list = saved.isEmpty ? [rootURL] : saved
        _roots = State(initialValue: list.map { FileNode(url: $0, isDirectory: true) })
        _expanded = State(initialValue: Set(list))   // 최상위 폴더는 기본 펼침
    }

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(flatten(roots), id: \.node) { item in
                    row(for: item.node, depth: item.depth)
                        .contentShape(Rectangle())
                        .listRowBackground(state.selectedFile == item.node
                            ? Color.accentColor.opacity(0.22) : Color.clear)
                        .onTapGesture {
                            if item.node.isDirectory { toggleFolder(item.node) }
                            else { state.selectedFile = item.node }
                        }
                        .contextMenu {
                            Button("새 파일") { newFile(in: item.node) }
                            Button("새 폴더") { newFolder(in: item.node) }
                            Button("폴더 추가…") { addFolder() }
                            Divider()
                            Button("이름 바꾸기") { beginRename(item.node) }
                            if isRoot(item.node) {
                                Button("사이드바에서 제거") { removeRoot(item.node) }
                            }
                            Button("삭제(휴지통으로)", role: .destructive) { delete(item.node) }
                        }
                }
            }
            // 빈 공간 우클릭
            .contextMenu {
                Button("새 파일") { newFile(in: nil) }
                Button("새 폴더") { newFolder(in: nil) }
                Button("폴더 추가…") { addFolder() }
            }
            .navigationTitle("폴더")
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
                    Button("폴더 추가", systemImage: "folder.badge.plus") { addFolder() }
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

    private func isRoot(_ node: FileNode) -> Bool { roots.contains { $0.url == node.url } }

    private func persistRoots() {
        UserDefaults.standard.set(roots.map { $0.url.path }, forKey: "folders")
    }

    // 기존 폴더를 사이드바에 추가 (VS Code "작업 공간에 폴더 추가")
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "추가"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !roots.contains(where: { $0.url == url }) else {
            statusMessage = "이미 추가된 폴더"
            return
        }
        roots.append(FileNode(url: url, isDirectory: true))
        expanded.insert(url)
        persistRoots()
    }

    // 사이드바에서만 제거(디스크의 폴더는 그대로)
    private func removeRoot(_ node: FileNode) {
        roots.removeAll { $0.url == node.url }
        expanded.remove(node.url)
        if state.selectedFile?.url.path.hasPrefix(node.url.path) == true {
            state.selectedFile = nil
            text = ""
        }
        persistRoots()
    }

    // 대상 폴더 결정: 선택 항목이 폴더면 그 안, 파일이면 같은 폴더, 없으면 첫 최상위 폴더
    private func targetDir(_ node: FileNode?) -> URL {
        let base = node ?? state.selectedFile
        guard let base else {
            return roots.first?.url ?? FileManager.default.homeDirectoryForCurrentUser
        }
        return base.isDirectory ? base.url : base.url.deletingLastPathComponent()
    }

    private func newFile(in node: FileNode? = nil) {
        let dir = targetDir(node)
        guard let name = promptForName(title: "새 마크다운 파일", confirmTitle: "만들기", info: dir.path) else { return }
        var fileName = name
        if !fileName.lowercased().hasSuffix(".md") { fileName += ".md" }

        let newURL = dir.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            statusMessage = "이미 있는 파일: \(fileName)"
            return
        }
        FileManager.default.createFile(atPath: newURL.path, contents: Data())

        if let node, node.isDirectory { expanded.insert(node.url) }   // 폴더 안에 만들면 펼쳐서 보이게
        reloadTree()
        state.selectedFile = FileNode(url: newURL, isDirectory: false)
    }

    private func newFolder(in node: FileNode? = nil) {
        let dir = targetDir(node)
        guard let name = promptForName(title: "새 폴더", confirmTitle: "만들기", info: dir.path) else { return }
        let newURL = dir.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            statusMessage = "이미 있는 폴더: \(name)"
            return
        }
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            if let node, node.isDirectory { expanded.insert(node.url) }
            expanded.insert(newURL)
            reloadTree()
        } catch {
            statusMessage = "폴더 생성 실패: \(error.localizedDescription)"
        }
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
        roots = roots.map { FileNode(url: $0.url, isDirectory: true) }
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
