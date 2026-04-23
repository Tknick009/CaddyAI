import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var backendText: String = ""
    @State private var saveStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $backendText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save") { save() }
                    if let saveStatus {
                        Text(saveStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    Link("Source", destination: URL(string: "https://github.com/Tknick009/CaddyAI")!)
                }
            }
            .navigationTitle("Settings")
            .onAppear { backendText = state.backendBaseURL.absoluteString }
        }
    }

    private func save() {
        guard let url = URL(string: backendText), url.scheme != nil else {
            saveStatus = "Invalid URL."
            return
        }
        state.backendBaseURL = url
        state.persist()
        saveStatus = "Saved."
    }
}
