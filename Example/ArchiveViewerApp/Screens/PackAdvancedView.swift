import SwiftUI

struct PackAdvancedView: View {
    let sources: [URL]
    @Binding var name: String
    @Binding var recipe: ArchiveOperations.Recipe
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Saves as \(fileName).")
                    .font(DS.Font.detail)
                    .foregroundStyle(.secondary)
            }

            Section("Container") {
                Picker("Container", selection: $recipe.container) {
                    ForEach(ArchiveOperations.Container.allCases) { container in
                        Text(container.title).tag(container)
                    }
                }
                .onChange(of: recipe.container) { _, container in
                    if !container.usesExternalFilter {
                        recipe.filter = .none
                    }
                }
            }

            Section {
                Picker("Method", selection: $recipe.filter) {
                    ForEach(ArchiveOperations.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .disabled(!recipe.container.usesExternalFilter)
            } header: {
                Text("Compression")
            } footer: {
                Text(
                    recipe.container.usesExternalFilter
                        ? "Applied around tar and cpio."
                        : "Zip and 7-Zip compress on their own."
                )
            }

            Section {
                Stepper(value: $recipe.compressionLevel, in: 0 ... 9) {
                    LabeledContent("Level", value: recipe.compressionLevel.formatted())
                }
            } footer: {
                Text("0 is fastest. 9 is smallest. Not every format uses this number.")
            }

            Section {
                Toggle("Skip Hidden Files", isOn: $recipe.skipHidden)
            }

            Section {
                Button("Create Archive") {
                    create()
                }
                .disabled(sources.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                if sources.isEmpty {
                    Text("Choose files on the Pack tab first.")
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fileName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Archive" : trimmed
        return "\(base).\(recipe.pathExtension)"
    }

    private func create() {
        let destination = SampleWorkspace.packs.appendingPathComponent(fileName)
        model.confirm(
            "Create Archive?",
            message: "“\(fileName)” will be saved to Archives inside this app.",
            confirm: "Create"
        ) {
            model.jobs.create(sources: sources, to: destination, recipe: recipe)
        }
    }
}
