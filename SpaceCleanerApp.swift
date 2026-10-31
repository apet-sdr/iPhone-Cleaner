import SwiftUI

@main
struct SpaceCleanerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

func formatBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}
