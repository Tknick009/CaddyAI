import SwiftUI
import UniformTypeIdentifiers
import CaddyAICore

/// For v1 the app opens the system file picker, uploads the CSV to the
/// backend's `/launch-monitor/import`, and shows the parsed shots. The
/// user can then map any unmatched vendor club names to their own clubs.
struct LaunchMonitorImportView: View {
    @EnvironmentObject private var state: AppState
    @State private var showPicker = false
    @State private var status: String = "Pick a CSV exported from your launch monitor."
    @State private var shots: [Shot] = []
    @State private var loading = false

    var body: some View {
        List {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .disabled(loading)
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }

            if !shots.isEmpty {
                Section("Shots (\(shots.count))") {
                    ForEach(shots) { shot in
                        ShotRow(shot: shot, bag: state.bag)
                    }
                }
            }
        }
        .navigationTitle("Launch monitor")
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            switch result {
            case .success(let url): Task { await upload(url) }
            case .failure(let err): status = "Picker error: \(err.localizedDescription)"
            }
        }
    }

    private func upload(_ url: URL) async {
        loading = true
        status = "Uploading…"
        defer { loading = false }

        guard url.startAccessingSecurityScopedResource() else {
            status = "Could not open file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            status = "Could not read file."
            return
        }

        var request = URLRequest(url: state.backendBaseURL.appendingPathComponent("/launch-monitor/import"))
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n")
        append("Content-Type: text/csv\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"vendor\"\r\n\r\nauto\r\n")
        append("--\(boundary)--\r\n")
        request.httpBody = body

        do {
            let (respData, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                status = "Backend error: HTTP \(http.statusCode)"
                return
            }
            let parsed = try CaddyAIJSON.decoder.decode([Shot].self, from: respData)
            shots = parsed
            status = "Imported \(parsed.count) shots."
        } catch {
            status = "Upload failed: \(error.localizedDescription)"
        }
    }
}

private struct ShotRow: View {
    let shot: Shot
    let bag: Bag

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(clubName).font(.headline)
                Text(shot.source.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(Int(shot.distanceYards)) yd")
                if let carry = shot.carryYards {
                    Text("carry \(Int(carry))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var clubName: String {
        if shot.clubId.isEmpty {
            return "Unmapped club"
        }
        return bag.clubs.first(where: { $0.id == shot.clubId })?.name ?? shot.clubId
    }
}
