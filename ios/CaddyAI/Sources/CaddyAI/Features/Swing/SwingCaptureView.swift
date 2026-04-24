import SwiftUI
import AVFoundation
import CaddyAICore

/// Camera-first capture flow. The live preview takes the full screen; all
/// controls sit on glass panels so the coach can scan the frame at a glance.
struct SwingCaptureView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var capture = SwingCaptureSession()
    @State private var selectedClubKind: ClubKind = .iron
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

                // Dim the camera edges a touch so white text has contrast.
                LinearGradient(
                    colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    modePill
                    Spacer()
                    if let pending = pendingFirstAngle {
                        pendingBanner(for: pending)
                            .padding(.bottom, Theme.Spacing.l)
                    }
                    if capture.isRecording {
                        recordingChip.padding(.bottom, Theme.Spacing.l)
                    }
                    bottomControls
                }

                if analyzing {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    VStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(.white).scaleEffect(1.4)
                        Text("Analyzing swing…")
                            .font(Theme.Type.bodyStrong)
                            .foregroundStyle(.white)
                    }
                    .padding(Theme.Spacing.xl)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                requestCameraPermissionIfNeeded()
                capture.configure()
            }
            .onDisappear { capture.stop() }
            .alert("Camera error", isPresented: .constant(capture.lastError != nil)) {
                Button("OK") { capture.lastError = nil }
            } message: { Text(capture.lastError ?? "") }
            .navigationDestination(isPresented: $showReview) { SwingReviewView() }
        }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack(alignment: .center) {
            clubMenu
            Spacer()
            handMenu
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.m)
    }

    private var clubMenu: some View {
        Menu {
            ForEach(ClubKind.allCases, id: \.self) { k in
                Button(k.rawValue.capitalized) { selectedClubKind = k; Haptics.selection() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "target").font(.system(size: 13, weight: .semibold))
                Text(selectedClubKind.rawValue.capitalized).font(Theme.Type.bodyStrong)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }

    private var handMenu: some View {
        Picker("Hand", selection: $state.preferredHandedness) {
            Text("R").tag(Handedness.right)
            Text("L").tag(Handedness.left)
        }
        .pickerStyle(.segmented)
        .frame(width: 80)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private var modePill: some View {
        HStack(spacing: 0) {
            modeButton("Face", .face2D)
            modeButton("DTL", .dtl2D)
            if SwingCaptureSession.supports3D {
                modeButton("3D", .pose3D)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .padding(.top, Theme.Spacing.m)
        .disabled(capture.isRecording || pendingFirstAngle != nil)
    }

    private func modeButton(_ label: String, _ mode: SwingCaptureMode) -> some View {
        let active = capture.mode == mode
        return Button {
            capture.mode = mode; Haptics.selection()
        } label: {
            Text(label)
                .font(Theme.Type.caption)
                .foregroundStyle(active ? Theme.Palette.primary : .white)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Color.white : Color.clear)
                )
        }
    }

    private var recordingChip: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Palette.danger).frame(width: 9, height: 9)
                .opacity(Double(Int(Date().timeIntervalSince1970 * 2) % 2))
            Text("REC · \(capture.framesCollected) frames")
                .font(Theme.Type.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 8)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private func pendingBanner(for pending: SwingCaptureResult) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(pendingPrompt(for: pending))
                .font(Theme.Type.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(Capsule().fill(Theme.Palette.accent.opacity(0.85)))

            HStack(spacing: Theme.Spacing.s) {
                Button("Analyze this angle") {
                    let first = pending
                    pendingFirstAngle = nil
                    Task { await analyze(first) }
                }
                .buttonStyle(.primaryPill(tint: .white, fullWidth: false))
                .foregroundStyle(Theme.Palette.primary)
                .disabled(analyzing || capture.isRecording)

                Button("Cancel") { pendingFirstAngle = nil; Haptics.selection() }
                    .buttonStyle(.secondaryPill(fullWidth: false))
                    .disabled(analyzing || capture.isRecording)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var bottomControls: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                Haptics.tap()
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
                        .frame(width: 86, height: 86)
                    RoundedRectangle(cornerRadius: capture.isRecording ? 8 : 34, style: .continuous)
                        .fill(capture.isRecording ? Theme.Palette.danger : .white)
                        .frame(width: capture.isRecording ? 36 : 68,
                               height: capture.isRecording ? 36 : 68)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: capture.isRecording)
                }
            }
            .disabled(!capture.isRunning || analyzing)

            Text(capture.isRecording ? "Tap to stop" : "Tap to record")
                .font(Theme.Type.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, Theme.Spacing.l)
        }
    }

    // MARK: - Decision flow (unchanged logic)

    private func handleCapture(_ result: SwingCaptureResult) async {
        if case .threeD = result {
            await analyze(result)
            return
        }
        guard case let .twoD(mode, _) = result else { return }

        if let first = pendingFirstAngle,
           case let .twoD(firstMode, _) = first,
           firstMode != mode
        {
            pendingFirstAngle = nil
            await fuse(first: first, second: result)
            return
        }

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
            capture, handedness: state.preferredHandedness, clubKind: selectedClubKind
        ) else {
            self.capture.lastError = "Could not read a full swing. Frame yourself head-to-toe and try again."
            Haptics.error()
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
            handedness: state.preferredHandedness, clubKind: selectedClubKind
        ) else {
            self.capture.lastError = "Neither capture was usable. Re-record and try again."
            Haptics.error()
            return
        }
        await postToCoach(metrics)
    }

    private func postToCoach(_ metrics: SwingMetrics) async {
        state.lastSwingMetrics = metrics
        do {
            let report = try await state.api.coachSwing(metrics)
            state.lastSwingReport = report
            Haptics.success()
            showReview = true
        } catch {
            state.lastSwingReport = nil
            capture.lastError = "Coach unavailable: \(error.localizedDescription)"
            Haptics.warning()
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
