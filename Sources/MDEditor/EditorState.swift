import Observation

// ponytail: single shared object so the menu bar (App.commands) and the toolbar
// (ContentView) can both drive the same editor without threading state through init.
@Observable
final class EditorState {
    var selectedFile: FileNode?
    let controller = EditorController()
}
