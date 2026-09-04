import SwiftUI

struct PackView: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Button {
                        picking = true
                    } label: {
                        Label(
                            model.packSources.isEmpty
                                ? "Choose Files"
                                : "\(model.packSources.count.formatted()) \(model.packSources.count == 1 ? "Item" : "Items")",
                            systemImage: "folder.badge.plus"
                        )
                    }
                    Button("Use Sample Files", systemImage: "doc.on.doc") {
                        useSample()
                    }
                    if !model.packSources.isEmpty {
                        ForEach(model.packSources, id: \.path) { url in
                            Label(url.lastPathComponent, systemImage: "doc")
                        }
                        .onDelete { offsets in
                            model.packSources.remove(atOffsets: offsets)
                        }
                    }
                } footer: {
                    Text("Folders are packed with the files inside them.")
                }

                Section("Format") {
                    Picker("Format", selection: $model.packRecipe.container) {
                        Text("Zip").tag(ArchiveOperations.Container.zip)
                        Text("tar.xz").tag(ArchiveOperations.Container.pax)
                        Text("7-Zip").tag(ArchiveOperations.Container.sevenZip)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.packRecipe.container) { _, container in
                        if container.usesExternalFilter {
                            if model.packRecipe.filter == .none {
                                model.packRecipe.filter = .xz
                            }
                        } else {
                            model.packRecipe.filter = .none
                        }
                    }
                    TextField("Name", text: $model.packName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Saves as \(fileName).")
                        .font(DS.Font.detail)
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink("Advanced") {
                        PackAdvancedView(
                            sources: model.packSources,
                            name: $model.packName,
                            recipe: $model.packRecipe
                        )
                    }
                }

                Section {
                    Button("Create Archive") {
                        create()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(
                        model.jobs.isBusy
                            || model.packSources.isEmpty
                            || model.packName.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Pack")
            .sheet(isPresented: $picking) {
                DocumentPicker(allowsMultipleSelection: true) { urls in
                    model.packSources.append(contentsOf: urls)
                }
                .ignoresSafeArea()
            }
            .onAppear {
                model.packRecipe.skipHidden = model.skipHidden
            }
        }
    }

    private var fileName: String {
        let trimmed = model.packName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.replacingOccurrences(of: "/", with: "-")
        let base = (cleaned.isEmpty || cleaned == "." || cleaned == "..") ? "Archive" : cleaned
        return "\(base).\(model.packRecipe.pathExtension)"
    }

    private func useSample() {
        do {
            model.packSources = [try SampleWorkspace.makeSourceTree()]
        } catch {
            model.reportFailure("Unable to Build Sample", error)
        }
    }

    private func create() {
        let destination = SampleWorkspace.packs.appendingPathComponent(fileName)
        model.confirm(
            "Create Archive?",
            message: "“\(fileName)” will be saved to Archives inside this app.",
            confirm: "Create"
        ) {
            model.jobs.create(sources: model.packSources, to: destination, recipe: model.packRecipe)
        }
    }
}
