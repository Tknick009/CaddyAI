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

    /// If set, we've already captured one of the two angles and the next
    /// button press captures the complementary angle and fuses them.
    @State private var pendingFirstAngle: SwingCaptureResult?

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
                    .padding(.horizontal)
                    .padding(.top)

                    Picker("Mode", selection: $capture.mode) {
                        Text("Face-on").tag(SwingCaptureMode.face2D)
                        Text("Down-the-line").tag(SwingCaptureMode.dtl2D)
                        if SwingCaptureSession.supports3D {
                            Text("3D pose").tag(SwingCaptureMode.pose3D)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .background(.ultraThinMaterial)
                    .disabled(capture.isRecording || pendingFirstAngle != nil)

                    if let pending = pendingFirstAngle {
                        Text(pendingPrompt(for: pending))
                            .font(.footnote.bold())
                            .padding(8)
                            .background(.yellow.opacity(0.85))
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                            .padding(.top, 4)
                    }

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
                                capture.stopRecording { result in
                                    Task { await handleCapture(result) }
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

    /// Decides whether a fresh 2D capture should be held as the first
    /// half of a face-on + down-the-line fusion, or analyzed immediately.
    private func handleCapture(_ result: SwingCaptureResult) async {
        // 3D captures never need fusion.
        if case .threeD = result {
            await analyze(result)
            return
        }
        guard case let .twoD(mode, _) = result else { return }

        // If we already have a capture from the *other* 2D angle, fuse.
        if let first = pendingFirstAngle,
           case let .twoD(firstMode, _) = first,
           firstMode != mode
        {
            pendingFirstAngle = nil
            await fuse(first: first, second: result)
            return
        }

        // Otherwise: offer to record the complementary angle for fusion.
        if mode == .face2D || mode == .dtl2D {
            pendingFirstAngle = result
            capture.mode = (mode == .face2D) ? .dtl2D : .face2D
        }
    }

    private func pendingPrompt(for pending: SwingCaptureResult) -> String {
        guard case let .twoD(mode, _) = pending else { return "" }
        switch mode {
        case .face2D: return "Now record a down-the-line view for fusion, or tap Analyze."
        case .dtl2D: return "Now record a face-on view for fusion, or tap Analyze."
        case .pose3D: return ""
        }
    }

    private func analyze(_ capture: SwingCaptureResult) async {
        analyzing = true
        defer { analyzing = false }
        guard let metrics = SwingAnalyzerFacade.analyze(
            capture, handedness: handedness, clubKind: selectedClubKind
        ) else {
            self.capture.lastError = "Could not read a full swing. Frame yourself head-to-toe and try again."
            return
        }
        await postToCoach(metrics)
    }

    private func fuse(first: SwingCaptureResult, second: SwingCaptureResult) async {
        analyzing = true
        defer { analyzing = false }
        let (fo, dtl): (SwingCaptureResult?, SwingCaptureResult?)
        if case let .twoD(mode, _) = first, mode == .face2D {
            fo = first; dtl = second
        } else {
            fo = second; dtl = first
        }
        guard let metrics = SwingAnalyzerFacade.fuse(
            faceOn: fo, downTheLine: dtl,
            handedness: handedness, clubKind: selectedClubKind
        ) else {
            self.capture.lastError = "Neither capture was usable. Re-record and try again."
            return
        }
        await postToCoach(metrics)
    }

    private func postToCoach(_ metrics: SwingMetrics) async {
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
