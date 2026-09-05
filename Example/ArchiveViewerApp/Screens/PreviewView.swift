import SwiftUI
import UIKit

struct PreviewView: View {
    let entryPath: String
    @Environment(AppModel.self) private var model
    @State private var payload: ArchiveOperations.Preview?
    @State private var failed: String?

    var body: some View {
        Group {
            if let payload {
                content(payload)
            } else if let failed {
                EmptyStateCard(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to Preview",
                    message: failed
                )
            } else {
                ProgressView("Reading…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: UnpackRoute.extractSingle(entryPath)) {
                    Label("Extract", systemImage: "square.and.arrow.down")
                }
            }
        }
        .task(id: entryPath) { await load() }
    }

    @ViewBuilder
    private func content(_ payload: ArchiveOperations.Preview) -> some View {
        if payload.totalSize == 0, entry(in: model.inspectEntries)?.isDirectory == true {
            EmptyStateCard(
                systemImage: "folder",
                title: "Folder",
                message: "Folders have no preview. Extract this path to recreate it on disk."
            )
        } else if let image = UIImage(data: payload.data) {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
        } else if let text = decodeText(payload.data) {
            ScrollView {
                Text(text)
                    .font(DS.Font.code)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Padding.l)
            }
            .safeAreaInset(edge: .bottom) {
                if payload.truncated {
                    Text("Showing the first \(Formatters.bytes.string(fromByteCount: Int64(payload.data.count))) of \(Formatters.bytes.string(fromByteCount: payload.totalSize)).")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
        } else {
            EmptyStateCard(
                systemImage: "doc",
                title: "No Preview",
                message: "This file is \(Formatters.bytes.string(fromByteCount: payload.totalSize)). Extract it to open it in another app."
            )
        }
    }

    private var name: String {
        entryPath.split(separator: "/").last.map(String.init) ?? entryPath
    }

    private func entry(in entries: [ArchiveOperations.Entry]) -> ArchiveOperations.Entry? {
        entries.first { $0.path == entryPath }
    }

    private func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8), text.contains(where: { !$0.isASCII || $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation || $0.isSymbol }) {
            if data.contains(0) { return nil }
            return text
        }
        return nil
    }

    private func load() async {
        guard let url = model.inspectURL else {
            failed = "Open an archive first."
            return
        }
        do {
            let preview = try await Task.detached(priority: .userInitiated) {
                try ArchiveOperations.preview(archive: url, entry: entryPath)
            }.value
            payload = preview
            AppLog.info(.archive, "previewed \(entryPath)")
        } catch {
            failed = error.localizedDescription
        }
    }
}
