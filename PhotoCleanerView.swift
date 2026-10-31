import SwiftUI
import Photos

@MainActor
final class PhotoScanner: ObservableObject {
    @Published var sections: [CleanSection] = []
    @Published var selected = Set<String>()
    @Published var scanning = false
    @Published var denied = false
    @Published var scanned = false

    func scan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { denied = true; return }
        denied = false
        scanning = true
        selected = []
        let found = await Task.detached(priority: .userInitiated) { PhotoScanner.fetch() }.value
        sections = [
            CleanSection(id: "videos", title: "Large videos (100 MB+)", rows: found.videos),
            CleanSection(id: "shots", title: "Screenshots", rows: found.screenshots),
        ].filter { !$0.rows.isEmpty }
        scanning = false
        scanned = true
    }

    nonisolated static func fetch() -> (videos: [CleanRow], screenshots: [CleanRow]) {
        var videos: [CleanRow] = []
        var shots: [CleanRow] = []
        let df = DateFormatter()
        df.dateStyle = .medium
        let all = PHAsset.fetchAssets(with: nil)
        all.enumerateObjects { asset, _, _ in
            let isShot = asset.mediaSubtypes.contains(.photoScreenshot)
            let isVideo = asset.mediaType == .video
            guard isShot || isVideo else { return }
            let size = fileSize(asset)
            let date = asset.creationDate.map { df.string(from: $0) } ?? "Unknown date"
            let row = CleanRow(
                id: asset.localIdentifier,
                title: isVideo ? "Video · \(Int(asset.duration))s" : "Screenshot",
                subtitle: date,
                size: size,
                photoID: asset.localIdentifier
            )
            if isVideo && size >= 100_000_000 { videos.append(row) }
            if isShot { shots.append(row) }
        }
        return (videos.sorted { $0.size > $1.size }, shots.sorted { $0.size > $1.size })
    }

    // fileSize isn't a documented property, but this key is widely used and works on current iOS.
    nonisolated static func fileSize(_ asset: PHAsset) -> Int64 {
        let res = PHAssetResource.assetResources(for: asset)
        guard let r = res.first(where: { $0.type == .photo || $0.type == .video }) ?? res.first else { return 0 }
        if let n = r.value(forKey: "fileSize") as? NSNumber { return n.int64Value }
        return 0
    }

    func deleteSelected() async {
        let ids = selected
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
        do {
            // iOS also shows its own confirmation. Items go to Recently Deleted for 30 days.
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            sections = sections.map { s in
                var s = s
                s.rows.removeAll { ids.contains($0.id) }
                return s
            }.filter { !$0.rows.isEmpty }
            selected = []
        } catch {
            // User tapped "Don't Allow" on the system prompt, or the change failed. Keep selection.
        }
    }
}

struct PhotoCleanerView: View {
    @StateObject private var scanner = PhotoScanner()

    var body: some View {
        NavigationStack {
            Group {
                if scanner.scanning {
                    ProgressView("Scanning…")
                } else if scanner.denied {
                    ContentUnavailableView("Photos access needed", systemImage: "photo",
                        description: Text("Allow access in Settings → Privacy & Security → Photos."))
                } else if !scanner.scanned {
                    ContentUnavailableView {
                        Label("Scan your library", systemImage: "magnifyingglass")
                    } description: {
                        Text("Finds large videos and screenshots to review.")
                    } actions: {
                        Button("Scan") { Task { await scanner.scan() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if scanner.sections.isEmpty {
                    ContentUnavailableView("Nothing to clean", systemImage: "checkmark.circle")
                } else {
                    CleanupList(
                        sections: scanner.sections,
                        selected: $scanner.selected,
                        permanentWarning: "Items move to Recently Deleted and are removed after 30 days."
                    ) { await scanner.deleteSelected() }
                }
            }
            .navigationTitle("Photos")
            .toolbar {
                if scanner.scanned {
                    Button("Rescan") { Task { await scanner.scan() } }
                }
            }
        }
    }
}

struct PhotoThumb: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 48, height: 48)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            guard image == nil,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
            else { return }
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill, options: opts
            ) { img, _ in
                if let img { image = img }
            }
        }
    }
}
