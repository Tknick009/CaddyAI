import Foundation
import AVFoundation
import CaddyAICore

/// Capture mode for a swing recording.
///
/// `face2D` / `dtl2D` run `VNDetectHumanBodyPoseRequest` and produce
/// `[PoseFrame]` — the 2D swing analyzer handles these, and two
/// captures can be fused by `MultiAngleSwingAnalyzer`.
///
/// `pose3D` runs `VNDetectHumanBodyPose3DRequest` (iOS 17+) and
/// produces `[Pose3DFrame]`, which `SwingAnalyzer3D` consumes directly
/// — a single capture yields honest turn, plane, and attack-angle
/// numbers without needing two viewpoints.
enum SwingCaptureMode: Equatable, Hashable {
    case face2D
    case dtl2D
    case pose3D
}

/// Container for whichever kind of frames a capture collected. The UI
/// doesn't need to care which — it just hands this blob to
/// `SwingAnalyzerFacade` on the way to the coach.
enum SwingCaptureResult {
    case twoD(mode: SwingCaptureMode, frames: [PoseFrame])
    case threeD(frames: [Pose3DFrame])
}

/// Camera capture for swing recording.
///
/// We run the capture at the highest frame rate the device reports (up
/// to 240 fps) and hand each frame to the pose estimator the current
/// `mode` selects. Frames are collected into a buffer while the user
/// holds "record" — stopping returns the buffer as a `SwingCaptureResult`.
final class SwingCaptureSession: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var framesCollected = 0
    @Published var mode: SwingCaptureMode = .face2D
    @Published var lastError: String?

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let queue = DispatchQueue(label: "ai.caddyai.capture")
    private let poseEstimator2D = PoseEstimator()
    private var poseEstimator3D: Any? = {
        if #available(iOS 17.0, *) {
            return PoseEstimator3D()
        } else {
            return nil
        }
    }()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var buffer2D: [PoseFrame] = []
    private var buffer3D: [Pose3DFrame] = []
    private var bufferStart: TimeInterval = 0

    override init() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer
        super.init()
    }

    /// Whether 3D pose is available on this device + OS combination.
    static var supports3D: Bool {
        if #available(iOS 17.0, *) { return true } else { return false }
    }

    func configure() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { self.lastError = "No back camera available." }
                return
            }
            self.applyHighestFrameRate(on: device)
            guard
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.lastError = "Could not open camera." }
                return
            }
            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
                self.videoOutput = output
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func startRecording() {
        queue.async { [weak self] in
            self?.buffer2D.removeAll(keepingCapacity: true)
            self?.buffer3D.removeAll(keepingCapacity: true)
            self?.bufferStart = CACurrentMediaTime()
            DispatchQueue.main.async {
                self?.isRecording = true
                self?.framesCollected = 0
            }
        }
    }

    /// Stops recording and returns the collected capture.
    func stopRecording(_ completion: @escaping (SwingCaptureResult) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let out: SwingCaptureResult
            switch self.mode {
            case .pose3D:
                out = .threeD(frames: self.buffer3D)
            case .face2D, .dtl2D:
                out = .twoD(mode: self.mode, frames: self.buffer2D)
            }
            DispatchQueue.main.async {
                self.isRecording = false
                completion(out)
            }
        }
    }

    private func applyHighestFrameRate(on device: AVCaptureDevice) {
        var best: (AVCaptureDevice.Format, Double)?
        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                let max = range.maxFrameRate
                if best == nil || max > (best?.1 ?? 0) {
                    best = (format, min(max, 240))
                }
            }
        }
        guard let (format, fps) = best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(fps))
            device.unlockForConfiguration()
        } catch {
            // Non-fatal: keep default frame rate.
        }
    }
}

extension SwingCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording else { return }
        let t = CACurrentMediaTime() - bufferStart
        switch mode {
        case .pose3D:
            if #available(iOS 17.0, *), let est = poseEstimator3D as? PoseEstimator3D,
               let frame = est.estimate(sampleBuffer, timestamp: t) {
                buffer3D.append(frame)
                let count = buffer3D.count
                DispatchQueue.main.async { self.framesCollected = count }
            }
        case .face2D, .dtl2D:
            if let frame = poseEstimator2D.estimate(sampleBuffer, timestamp: t) {
                buffer2D.append(frame)
                let count = buffer2D.count
                DispatchQueue.main.async { self.framesCollected = count }
            }
        }
    }
}
