import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(InterfaceTextSize.key) private var textStep = 0

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("Skip Hidden Files", isOn: $model.skipHidden)
                    Picker("Default Format", selection: $model.defaultRecipe.container) {
                        ForEach(ArchiveOperations.Container.allCases) { container in
                            Text(container.title).tag(container)
                        }
                    }
                    .onChange(of: model.defaultRecipe.container) { _, container in
                        if !container.usesExternalFilter {
                            model.defaultRecipe.filter = .none
                        } else if model.defaultRecipe.filter == .none {
                            model.defaultRecipe.filter = .xz
                        }
                    }
                } header: {
                    Text("Packing")
                } footer: {
                    Text("Used when Pack opens. Advanced options still apply to one archive at a time.")
                }

                Section("Text Size") {
                    Stepper(value: $textStep, in: InterfaceTextSize.steps) {
                        Text("Interface Text")
                    }
                    Text("Aa")
                        .font(DS.Font.title)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Section("Diagnostics") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Logs", systemImage: "doc.text")
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Archive")
                    LabeledContent("Version", value: version)
                    Text("Formats are detected from the file itself.")
                        .font(DS.Font.detail)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
