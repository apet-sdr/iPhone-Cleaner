import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            StorageView().tabItem { Label("Storage", systemImage: "internaldrive") }
            PhotoCleanerView().tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            FolderCleanerView().tabItem { Label("Files", systemImage: "folder") }
        }
    }
}

struct StorageView: View {
    @State private var total: Int64 = 0
    @State private var available: Int64 = 0

    private var used: Int64 { max(total - available, 0) }

    var body: some View {
        NavigationStack {
            List {
                Section("This iPhone") {
                    if total > 0 {
                        ProgressView(value: Double(used), total: Double(total))
                        HStack {
                            Text("Used \(formatBytes(used))")
                            Spacer()
                            Text("Free \(formatBytes(available))").foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    } else {
                        Text("Storage info unavailable")
                    }
                }

                Section("Other ways to save space (iOS settings)") {
                    tip("Offload unused apps", "Settings → General → iPhone Storage → Offload Unused Apps")
                    tip("Review big apps", "iPhone Storage lists apps by size. Delete and reinstall bloated ones.")
                    tip("Clear Safari data", "Settings → Apps → Safari → Clear History and Website Data")
                    tip("Empty Recently Deleted", "Photos → Albums → Recently Deleted → Select → Delete All")
                    tip("Optimize photos", "Settings → Photos → Optimize iPhone Storage (needs iCloud Photos)")
                    tip("Shrink new photos/videos", "Settings → Camera → Formats → High Efficiency")
                    tip("Review Messages attachments", "iPhone Storage → Messages → Review Large Attachments")
                }

                Section("About memory") {
                    Text("iOS manages RAM and GPU memory itself and gives apps no way to free it. Restarting the phone and force-quitting a misbehaving app are the only real options.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Storage")
            .onAppear(perform: load)
            .refreshable { load() }
        }
    }

    private func tip(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let v = try? url.resourceValues(forKeys: keys),
           let t = v.volumeTotalCapacity,
           let a = v.volumeAvailableCapacityForImportantUsage {
            total = Int64(t)
            available = a
        }
    }
}
