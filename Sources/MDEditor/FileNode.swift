import Foundation

// ponytail: eager one-level scan, no file-system watcher — reopen the folder if files change externally.
final class FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var id: URL { url }
    var name: String { url.lastPathComponent }

    lazy var children: [FileNode]? = isDirectory ? FileNode.loadChildren(of: url) : nil

    static func loadChildren(of url: URL) -> [FileNode] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return items
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { child in
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return FileNode(url: child, isDirectory: isDir)
            }
            // 폴더와 .md 파일만 노출 (png 등 나머지 파일은 숨김)
            .filter { $0.isDirectory || $0.url.pathExtension.lowercased() == "md" }
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
