import Foundation
import AVFoundation
import CaddyAICore

/// Camera capture for swing recording.
///
/// We run the capture at the highest frame rate the device reports (up
/// to 120 fps) and hand each frame to the pose estimator. Frames and
/// their extracted `PoseFrame`s are collected into a `[PoseFrame]`
/// buffer while the user holds down "record" — stopping returns the
/// buffer so the swing analyzer can chew on it.
final class SwingCaptureSession: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var framesCollected = 0
    @Published var lastError: String?

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let queue = DispatchQueue(label: "ai.caddyai.capture")
    private let poseEstimator = PoseEstimator()
    private var videoOutput: AVCaptureVideoDataOutput?
    private var buffer: [PoseFrame] = []
    private var bufferStart: TimeInterval = 0

    override init() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer
        super.init()
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
            self?.buffer.removeAll(keepingCapacity: true)
            self?.bufferStart = CACurrentMediaTime()
            DispatchQueue.main.async {
                self?.isRecording = true
                self?.framesCollected = 0
            }
        }
    }

    /// Stops recording and returns the collected pose frames.
    func stopRecording(_ completion: @escaping ([PoseFrame]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let out = self.buffer
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
        if let frame = poseEstimator.estimate(sampleBuffer, timestamp: t) {
            buffer.append(frame)
            let count = buffer.count
            DispatchQueue.main.async { self.framesCollected = count }
        }
    }
}
