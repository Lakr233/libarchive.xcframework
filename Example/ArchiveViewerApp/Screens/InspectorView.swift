import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let visible = filtered
        List {
            Section {
                summary
            }
            Section {
                if visible.isEmpty {
                    EmptyStateCard(
                        systemImage: "doc.text.magnifyingglass",
                        title: query.isEmpty ? "No Entries" : "No Matches",
                        message: query.isEmpty
                            ? "This archive has no entries."
                            : "No entry matches “\(query)”."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visible) { entry in
                        NavigationLink(value: UnpackRoute.preview(entry.path)) {
                            ArchiveEntryRow(entry: entry)
                        }
                        .contextMenu {
                            NavigationLink(value: UnpackRoute.preview(entry.path)) {
                                Label("Quick Preview", systemImage: "eye")
                            }
                            NavigationLink(value: UnpackRoute.extractSingle(entry.path)) {
                                Label("Extract This File", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                }
            } header: {
                Text(headerTitle(visible.count))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.inspectURL?.lastPathComponent ?? "Contents")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Extract All", systemImage: "square.and.arrow.down") {
                    extractAll()
                }
                .disabled(model.jobs.isBusy || model.inspectURL == nil || model.inspectEntries.isEmpty)
            }
        }
    }

    private var summary: some View {
        let files = model.inspectEntries.filter { !$0.isDirectory }
        let folders = model.inspectEntries.count - files.count
        let bytes = files.reduce(Int64(0)) { $0 + max(0, $1.size) }
        return HStack {
            stat("Files", files.count.formatted())
            stat("Folders", folders.formatted())
            stat("Unpacked", Formatters.bytes.string(fromByteCount: bytes))
        }
        .padding(.vertical, DS.Padding.s)
    }

    private func stat(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption.uppercased())
                .font(DS.Font.captionEmphasis)
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filtered: [ArchiveOperations.Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.inspectEntries }
        return model.inspectEntries.filter { $0.path.localizedCaseInsensitiveContains(trimmed) }
    }

    private func headerTitle(_ count: Int) -> String {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return count == 1 ? "1 Entry" : "\(count.formatted()) Entries"
        }
        return count == 1 ? "1 Match" : "\(count.formatted()) Matches"
    }

    private func extractAll() {
        guard let url = model.inspectURL else { return }
        let folder = SampleWorkspace.unpacks.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent,
            isDirectory: true
        )
        model.confirm(
            "Extract All?",
            message: "Files will be written to Unpacked inside this app.",
            confirm: "Extract"
        ) {
            model.jobs.extract(archive: url, to: folder, title: url.lastPathComponent)
        }
    }
}
