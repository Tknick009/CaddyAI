import SwiftUI
import AVFoundation
import CaddyAICore

struct SwingCaptureView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var capture = SwingCaptureSession()
    @State private var selectedClubKind: ClubKind = .iron
    @State private var handedness: Handedness = .right
    @State private var analyzing = false
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewView(layer: capture.previewLayer)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Picker("Club", selection: $selectedClubKind) {
                            ForEach(ClubKind.allCases, id: \.self) { k in
                                Text(k.rawValue.capitalized).tag(k)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)

                        Spacer()

                        Picker("Hand", selection: $handedness) {
                            Text("Right").tag(Handedness.right)
                            Text("Left").tag(Handedness.left)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding()
                    .background(.ultraThinMaterial)

                    Spacer()

                    if capture.isRecording {
                        Text("Recording — \(capture.framesCollected) frames")
                            .padding(8)
                            .background(.red.opacity(0.75))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 24) {
                        Button {
                            if capture.isRecording {
                                capture.stopRecording { frames in
                                    Task { await analyze(frames: frames) }
                                }
                            } else {
                                capture.startRecording()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .fill(capture.isRecording ? .red : .white)
                                    .frame(width: 64, height: 64)
                            }
                        }
                        .disabled(!capture.isRunning || analyzing)
                    }
                    .padding(.bottom, 32)
                }

                if analyzing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Analyzing swing…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Swing")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                requestCameraPermissionIfNeeded()
                capture.configure()
            }
            .onDisappear { capture.stop() }
            .alert("Camera error", isPresented: .constant(capture.lastError != nil)) {
                Button("OK") { capture.lastError = nil }
            } message: { Text(capture.lastError ?? "") }
            .navigationDestination(isPresented: $showReview) {
                SwingReviewView()
            }
        }
    }

    private func analyze(frames: [PoseFrame]) async {
        analyzing = true
        defer { analyzing = false }
        let analyzer = SwingAnalyzer()
        guard let metrics = analyzer.analyze(frames: frames, handedness: handedness, clubKind: selectedClubKind) else {
            capture.lastError = "Could not read a full swing. Frame yourself head-to-toe and try again."
            return
        }
        state.lastSwingMetrics = metrics
        do {
            let report = try await state.api.coachSwing(metrics)
            state.lastSwingReport = report
            showReview = true
        } catch {
            state.lastSwingReport = nil
            capture.lastError = "Coach unavailable: \(error.localizedDescription)"
            // Still let the user see local metrics.
            showReview = true
        }
    }

    private func requestCameraPermissionIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        default:
            break
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer = layer
        v.layer.addSublayer(layer)
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.setNeedsLayout()
    }

    final class PreviewUIView: UIView {
        weak var previewLayer: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
