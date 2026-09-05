import SwiftUI

struct ExtractSingleView: View {
    let entryPath: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let entry = model.inspectEntries.first { $0.path == entryPath }
        List {
            Section {
                LabeledContent("Name", value: name)
                LabeledContent("Path", value: entryPath)
                if let entry {
                    LabeledContent(
                        "Size",
                        value: entry.isDirectory
                            ? "Folder"
                            : Formatters.bytes.string(fromByteCount: entry.size)
                    )
                }
            }
            Section {
                LabeledContent("Saved To", value: "Unpacked")
                Text("Written into this app, then available in the Files app.")
                    .font(DS.Font.detail)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Extract File") {
                    extract()
                }
                .disabled(
                    model.jobs.isBusy
                        || model.inspectURL == nil
                        || ArchiveOperations.safeDestination(
                            directory: SampleWorkspace.unpacks,
                            relative: entryPath
                        ) == nil
                )
            }
        }
        .navigationTitle("Extract File")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var name: String {
        entryPath.split(separator: "/").last.map(String.init) ?? entryPath
    }

    private func extract() {
        guard let url = model.inspectURL else { return }
        guard ArchiveOperations.safeDestination(
            directory: SampleWorkspace.unpacks,
            relative: entryPath
        ) != nil else {
            model.reportFailure(
                "Unable to Extract",
                ArchiveOperations.Failure(errorDescription: "The archive contains an unsafe path.")
            )
            return
        }
        model.confirm(
            "Extract This File?",
            message: "“\(name)” will be written to Unpacked inside this app.",
            confirm: "Extract"
        ) {
            model.jobs.extractOne(archive: url, entry: entryPath, into: SampleWorkspace.unpacks)
        }
    }
}
