import Foundation
import SwiftUI
import CaddyAICore

/// Global state shared across tabs.
///
/// - `bag`: the player's current bag. Persisted to `UserDefaults` so the
///   user doesn't need an account to keep their clubs between launches.
/// - `rounds`: completed rounds (kept locally for v1).
/// - `api`: the configured backend client (base URL is user-editable in
///   Settings; defaults to `http://localhost:8000`).
@MainActor
final class AppState: ObservableObject {
    @Published var bag: Bag
    @Published var rounds: [Round]
    @Published var backendBaseURL: URL {
        didSet { api = APIClient(baseURL: backendBaseURL) }
    }
    @Published var lastSwingReport: CoachingReport?
    @Published var lastSwingMetrics: SwingMetrics?

    private(set) var api: APIClient

    private static let bagKey = "CaddyAI.bag"
    private static let roundsKey = "CaddyAI.rounds"
    private static let backendKey = "CaddyAI.backend_url"

    init() {
        let defaults = UserDefaults.standard

        if
            let data = defaults.data(forKey: Self.bagKey),
            let decoded = try? CaddyAIJSON.decoder.decode(Bag.self, from: data)
        {
            self.bag = decoded
        } else {
            self.bag = Bag.standard14
        }

        if
            let data = defaults.data(forKey: Self.roundsKey),
            let decoded = try? CaddyAIJSON.decoder.decode([Round].self, from: data)
        {
            self.rounds = decoded
        } else {
            self.rounds = []
        }

        let url: URL
        if
            let stored = defaults.string(forKey: Self.backendKey),
            let parsed = URL(string: stored)
        {
            url = parsed
        } else {
            url = URL(string: "http://localhost:8000")!
        }
        self.backendBaseURL = url
        self.api = APIClient(baseURL: url)
    }

    func persist() {
        let defaults = UserDefaults.standard
        if let data = try? CaddyAIJSON.encoder.encode(bag) {
            defaults.set(data, forKey: Self.bagKey)
        }
        if let data = try? CaddyAIJSON.encoder.encode(rounds) {
            defaults.set(data, forKey: Self.roundsKey)
        }
        defaults.set(backendBaseURL.absoluteString, forKey: Self.backendKey)
    }
}
