import Foundation
import SwiftUI
import UIKit
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
        didSet { api = APIClient(baseURL: backendBaseURL, deviceId: deviceId) }
    }
    let deviceId: String
    @Published var lastSwingReport: CoachingReport?
    @Published var lastSwingMetrics: SwingMetrics?
    /// Chosen once in onboarding, used to flip the pose skeleton in
    /// `SwingCaptureView`. Defaults to right. Persisted to UserDefaults.
    @Published var preferredHandedness: Handedness {
        didSet {
            UserDefaults.standard.set(preferredHandedness.rawValue, forKey: Self.handednessKey)
        }
    }

    private(set) var api: APIClient

    private static let bagKey = "CaddyAI.bag"
    private static let roundsKey = "CaddyAI.rounds"
    private static let backendKey = "CaddyAI.backend_url"
    private static let deviceIdKey = "CaddyAI.device_id"
    private static let handednessKey = "CaddyAI.handedness"
    static let onboardedKey = "CaddyAI.has_onboarded"

    /// Stable-per-install identifier used as the RAG memory key on the
    /// server. Falls back to a random UUID if `identifierForVendor` is
    /// unavailable and persists it in `UserDefaults`.
    private static func resolveDeviceId() -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Self.deviceIdKey), !stored.isEmpty {
            return stored
        }
        let new = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        defaults.set(new, forKey: Self.deviceIdKey)
        return new
    }

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
        let deviceId = Self.resolveDeviceId()
        self.deviceId = deviceId
        self.api = APIClient(baseURL: url, deviceId: deviceId)

        let handRaw = defaults.string(forKey: Self.handednessKey) ?? Handedness.right.rawValue
        self.preferredHandedness = Handedness(rawValue: handRaw) ?? .right
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
