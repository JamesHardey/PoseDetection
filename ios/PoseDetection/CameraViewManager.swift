import Foundation
import React
import AVFoundation
import Vision

@objc(CameraViewManager)
class CameraViewManager: RCTViewManager {
    
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    override func view() -> UIView! {
        return CameraView()
    }
    
    override class func moduleName() -> String! {
        return "CameraView"
    }
    
    @objc func setCameraType(_ node: NSNumber, cameraType: String) {
        DispatchQueue.main.async {
            if let component = self.bridge.uiManager.view(forReactTag: node) as? CameraView {
                component.setCameraType(cameraType)
            }
        }
    }
}

class CameraView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentCamera: AVCaptureDevice?
    
    private let poseValidator = PoseValidator()
    private let sidePoseValidator = SidePoseValidator()
    private let bodyPositionChecker = BodyPositionChecker()
    private let voiceFeedback = VoiceFeedbackProvider()
    
    private var countdownTimer: Timer?
    private var countdownValue = 3
    private var isCapturing = false
    private var latestSampleBuffer: CMSampleBuffer?
    private var processingQueue = DispatchQueue(label: "com.posedetection.processing", qos: .userInitiated)
    
    private enum PoseStage {
        case frontPose
        case sidePose
    }
    
    private var currentStage: PoseStage = .frontPose
    private var frontImagePath: String?
    private var sideImagePath: String?
    private var initialCameraType: String = "front"
    
    @objc var cameraType: NSString = "front" {
        didSet {
            initialCameraType = cameraType as String
            if captureSession == nil {
                setupCamera()
            }
        }
    }
    
    @objc var onCaptureStatus: RCTDirectEventBlock?
    @objc var onBothImagesCaptured: RCTDirectEventBlock?
    
    private let poseOverlayView = PoseOverlayView()
    
    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.boldSystemFont(ofSize: 72)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Add pose overlay
        addSubview(poseOverlayView)
        poseOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            poseOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            poseOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            poseOverlayView.topAnchor.constraint(equalTo: topAnchor),
            poseOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        addSubview(countdownLabel)
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            countdownLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    private func setupCamera() {
        // Check camera permission
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraAuthStatus != .authorized {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                } else {
                    print("Camera permission denied")
                }
            }
            return
        }
        
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        // Use camera based on prop (default: front)
        let position: AVCaptureDevice.Position = initialCameraType == "front" ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            print("Unable to access \(initialCameraType) camera")
            sendStatusEvent(status: "error", message: "Camera not available")
            return
        }
        
        currentCamera = camera
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.videoGravity = .resizeAspectFill
            previewLayer?.frame = bounds
            
            if let previewLayer = previewLayer {
                layer.addSublayer(previewLayer)
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
                DispatchQueue.main.async {
                    self?.sendStatusEvent(status: "camera_started", message: "Camera started and ready!")
                }
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        poseOverlayView.frame = bounds
    }
    
    @objc func setCameraType(_ type: String) {
        guard let session = captureSession else { return }
        
        session.beginConfiguration()
        
        // Remove existing inputs
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
        }
        
        let position: AVCaptureDevice.Position = type == "front" ? .front : .back
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.commitConfiguration()
            return
        }
        
        currentCamera = camera
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Error switching camera: \(error)")
        }
        
        session.commitConfiguration()
        
        // Reset detection state
        resetDetectionState()
    }
    
    private func resetDetectionState() {
        isCapturing = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 3
        DispatchQueue.main.async {
            self.countdownLabel.isHidden = true
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Store latest sample buffer for capture
        latestSampleBuffer = sampleBuffer
        
        guard !isCapturing else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Pose detection error: \(error)")
                return
            }
            
            guard let observations = request.results as? [VNHumanBodyPoseObservation],
                  let observation = observations.first else {
                return
            }
            
            do {
                let recognizedPoints = try observation.recognizedPoints(.all)
                self.processPose(recognizedPoints)
                
                // Update overlay with detected landmarks
                DispatchQueue.main.async {
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                    let imageSize = CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    )
                    self.poseOverlayView.updatePose(
                        recognizedPoints,
                        imageSize: imageSize,
                        perfect: false,
                        countdown: self.countdownValue,
                        counting: self.isCapturing
                    )
                }
            } catch {
                print("Error processing pose: \(error)")
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform request: \(error)")
        }
    }
    
    private func processPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        switch currentStage {
        case .frontPose:
            processFrontPose(landmarks)
        case .sidePose:
            processSidePose(landmarks)
        }
    }
    
    private func processFrontPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let (isValid, feedback) = bodyPositionChecker.checkPose(landmarks)
        
        // Voice feedback will handle main thread dispatch internally
        voiceFeedback.provideFeedback(feedback)
        
        if isValid {
            sendStatusEvent(status: "ready_to_capture", message: "Ready to capture front pose!")
            startCountdown(for: .frontPose)
        }
    }
    
    private func processSidePose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        if sidePoseValidator.isValidSidePose(landmarks) {
            sendStatusEvent(status: "ready_to_capture_side", message: "Ready to capture side pose!")
            startCountdown(for: .sidePose)
        } else {
            // Voice feedback will handle main thread dispatch internally
            voiceFeedback.provideFeedback("Turn sideways completely")
        }
    }
    
    private func startCountdown(for stage: PoseStage) {
        guard countdownTimer == nil else { return }
        
        isCapturing = true
        countdownValue = 3
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.countdownLabel.isHidden = false
            self.countdownLabel.text = "\(self.countdownValue)"
            
            // Schedule timer on main run loop
            self.countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                self.countdownValue -= 1
                
                if self.countdownValue > 0 {
                    self.countdownLabel.text = "\(self.countdownValue)"
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.countdownLabel.isHidden = true
                    self.captureImage(for: stage)
                }
            }
        }
    }
    
    private func captureImage(for stage: PoseStage) {
        guard let sampleBuffer = latestSampleBuffer else {
            print("No sample buffer available")
            isCapturing = false
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer")
            isCapturing = false
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create CGImage")
            isCapturing = false
            return
        }
        
        // Fix orientation based on camera position
        let orientation: UIImage.Orientation = currentCamera?.position == .front ? .leftMirrored : .right
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        
        saveImage(image, for: stage)
    }
    
    private func saveImage(_ image: UIImage, for stage: PoseStage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            isCapturing = false
            return
        }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = stage == .frontPose ? "front_pose_\(Date().timeIntervalSince1970).jpg" : "side_pose_\(Date().timeIntervalSince1970).jpg"
        let fileURL = cacheDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            
            if stage == .frontPose {
                frontImagePath = fileURL.path
                sendStatusEvent(status: "front_pose_captured", message: "Front pose captured! Turn sideways...")
                
                // Voice feedback will handle main thread dispatch internally
                voiceFeedback.provideFeedback("Great! Now turn sideways for the side pose")
                
                currentStage = .sidePose
                isCapturing = false
            } else {
                sideImagePath = fileURL.path
                sendStatusEvent(status: "both_poses_captured", message: "Both poses captured! Processing...")
                sendImagesToReactNative()
            }
            
        } catch {
            print("Error saving image: \(error)")
            isCapturing = false
        }
    }
    
    private func sendStatusEvent(status: String, message: String) {
        guard let onCaptureStatus = onCaptureStatus else { 
            print("Warning: onCaptureStatus is nil")
            return 
        }
        
        DispatchQueue.main.async {
            onCaptureStatus([
                "status": status,
                "message": message
            ])
        }
    }
    
    private func sendImagesToReactNative() {
        guard let frontPath = frontImagePath,
              let sidePath = sideImagePath else {
            print("Error: Missing image paths - front: \(frontImagePath ?? "nil"), side: \(sideImagePath ?? "nil")")
            return
        }
        
        guard let onBothImagesCaptured = onBothImagesCaptured else {
            print("Warning: onBothImagesCaptured is nil")
            return
        }
        
        DispatchQueue.main.async {
            onBothImagesCaptured([
                "frontImageUri": "file://\(frontPath)",
                "sideImageUri": "file://\(sidePath)"
            ])
        }
    }
    
    deinit {
        captureSession?.stopRunning()
        voiceFeedback.stop()
        countdownTimer?.invalidate()
    }
}
