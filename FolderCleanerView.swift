import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class FolderScanner: ObservableObject {
    @Published var sections: [CleanSection] = []
    @Published var selected = Set<String>()
    @Published var scanning = false
    @Published var scanned = false
    @Published var folderName = ""
    @Published var failedCount = 0
    private var folder: URL?

    func scan(folder: URL) async {
        self.folder = folder
        folderName = folder.lastPathComponent
        scanning = true
        selected = []
        failedCount = 0
        let ok = folder.startAccessingSecurityScopedResource()
        let result = await Task.detached(priority: .userInitiated) { FolderScanner.analyze(folder) }.value
        if ok { folder.stopAccessingSecurityScopedResource() }
        sections = result
        scanning = false
        scanned = true
    }

    nonisolated static func analyze(_ root: URL) -> [CleanSection] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, size: Int64, date: Date)] = []
        for case let url as URL in en {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            files.append((url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast))
        }

        let df = DateFormatter()
        df.dateStyle = .medium
        func row(_ f: (url: URL, size: Int64, date: Date)) -> CleanRow {
            CleanRow(id: f.url.path, title: f.url.lastPathComponent,
                     subtitle: df.string(from: f.date), size: f.size)
        }

        // Large files
        let large = files.filter { $0.size >= 10_000_000 }.sorted { $0.size > $1.size }.map(row)

        // Old files (not modified in a year, at least 1 MB)
        let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let old = files.filter { $0.date < cutoff && $0.size >= 1_000_000 }.sorted { $0.size > $1.size }.map(row)

        // Exact duplicates: same size, then same SHA-256. The oldest copy is kept, the rest are listed.
        var dupes: [CleanRow] = []
        let bySize = Dictionary(grouping: files.filter { $0.size > 0 }, by: \.size)
        for (_, group) in bySize where group.count > 1 {
            var byHash: [String: [(url: URL, size: Int64, date: Date)]] = [:]
            for f in group {
                if let h = hash(f.url) { byHash[h, default: []].append(f) }
            }
            for (_, same) in byHash where same.count > 1 {
                let sorted = same.sorted { $0.date < $1.date }
                dupes += sorted.dropFirst().map(row)
            }
        }
        dupes.sort { $0.size > $1.size }

        return [
            CleanSection(id: "dupes", title: "Duplicates (extra copies)", rows: dupes),
            CleanSection(id: "large", title: "Large files (10 MB+)", rows: large),
            CleanSection(id: "old", title: "Not modified in a year", rows: old),
        ].filter { !$0.rows.isEmpty }
    }

    nonisolated static func hash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let data = try? h.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func deleteSelected() async {
        guard let folder else { return }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        var deleted = Set<String>()
        var failed = 0
        for path in selected {
            do {
                try FileManager.default.removeItem(atPath: path)
                deleted.insert(path)
            } catch { failed += 1 }
        }
        failedCount = failed
        sections = sections.map { s in
            var s = s
            s.rows.removeAll { deleted.contains($0.id) }
            return s
        }.filter { !$0.rows.isEmpty }
        selected.subtract(deleted)
    }
}

struct FolderCleanerView: View {
    @StateObject private var scanner = FolderScanner()
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Group {
                if scanner.scanning {
                    ProgressView("Scanning \(scanner.folderName)…")
                } else if !scanner.scanned {
                    ContentUnavailableView {
                        Label("Pick a folder", systemImage: "folder")
                    } description: {
                        Text("Choose a folder in Files (Downloads, On My iPhone, iCloud Drive). The app only sees what you pick.")
                    } actions: {
                        Button("Choose Folder") { picking = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if scanner.sections.isEmpty {
                    ContentUnavailableView("Nothing to clean", systemImage: "checkmark.circle")
                } else {
                    VStack(spacing: 0) {
                        if scanner.failedCount > 0 {
                            Text("\(scanner.failedCount) files couldn't be deleted.")
                                .font(.footnote).foregroundStyle(.red).padding(.top, 8)
                        }
                        CleanupList(
                            sections: scanner.sections,
                            selected: $scanner.selected,
                            permanentWarning: "Files are deleted permanently. This can't be undone."
                        ) { await scanner.deleteSelected() }
                    }
                }
            }
            .navigationTitle(scanner.scanned ? scanner.folderName : "Files")
            .toolbar {
                if scanner.scanned {
                    Button("Change Folder") { picking = true }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await scanner.scan(folder: url) }
                }
            }
        }
    }
}
