import SwiftUI

struct CleanRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let size: Int64
    var photoID: String? = nil
}

struct CleanSection: Identifiable {
    let id: String
    let title: String
    var rows: [CleanRow]
}

/// Shared review screen: sections, per-item checkboxes, Select All / None, and a confirm-to-delete bar.
struct CleanupList: View {
    let sections: [CleanSection]
    @Binding var selected: Set<String>
    let permanentWarning: String
    let onDelete: () async -> Void
    @State private var confirm = false

    private var sizeByID: [String: Int64] {
        var d: [String: Int64] = [:]
        for s in sections { for r in s.rows { d[r.id] = r.size } }
        return d
    }

    // Counts each item once, even if it appears in more than one section.
    private var selectedBytes: Int64 {
        let map = sizeByID
        return selected.reduce(0) { $0 + (map[$1] ?? 0) }
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        Button { toggle(row.id) } label: { rowView(row) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("\(section.title) · \(section.rows.count)")
                        Spacer()
                        Button("Select All") { selected.formUnion(section.rows.map(\.id)) }
                            .buttonStyle(.borderless)
                        Button("None") { selected.subtract(section.rows.map(\.id)) }
                            .buttonStyle(.borderless)
                    }
                    .textCase(nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty {
                Button(role: .destructive) { confirm = true } label: {
                    Text("Delete \(selected.count) items · free \(formatBytes(selectedBytes))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
                .background(.bar)
            }
        }
        .confirmationDialog("Delete \(selected.count) items?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete \(formatBytes(selectedBytes))", role: .destructive) {
                Task { await onDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permanentWarning)
        }
    }

    private func rowView(_ row: CleanRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected.contains(row.id) ? Color.accentColor : Color.secondary)
            if let pid = row.photoID { PhotoThumb(id: pid) }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(1)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(formatBytes(row.size)).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
