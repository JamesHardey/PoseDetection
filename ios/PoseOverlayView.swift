import UIKit
import Vision
import CoreGraphics

// Shared pose types for ML Kit mapping
public struct RecognizedPointCompat {
    public let location: CGPoint
    public let confidence: Float
}

public typealias JointName = VNHumanBodyPoseObservation.JointName
public typealias PoseLandmarks = [JointName: RecognizedPointCompat]
import CoreGraphics

class PoseOverlayView: UIView {
    private var landmarks: PoseLandmarks?
    private var imageSize: CGSize = .zero
    private var accuracy: PoseValidator.PostureAccuracy?
    private var isPerfectPose: Bool = false
    private var countdownValue: Int = 0
    private var isCountingDown: Bool = false
    private var isMirrored: Bool = false

    // Target box similar to Android (5% inset with dashed yellow stroke)
    private let targetBoxInsets: CGFloat = 0.05
    private let targetStrokeColor = UIColor.yellow.cgColor
    private let targetFillColor = UIColor(red: 1, green: 1, blue: 0, alpha: 0.15).cgColor
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        clearsContextBeforeDrawing = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePose(_ newLandmarks: PoseLandmarks?, 
                    imageSize: CGSize,
                    accuracy: PoseValidator.PostureAccuracy? = nil,
                    perfect: Bool = false,
                    countdown: Int = 0,
                    counting: Bool = false,
                    mirrored: Bool = false) {
        self.landmarks = newLandmarks
        self.imageSize = imageSize
        self.accuracy = accuracy
        self.isPerfectPose = perfect
        self.countdownValue = countdown
        self.isCountingDown = counting
        self.isMirrored = mirrored
        
        print("🖼️ PoseOverlayView.updatePose called - landmarks: \(newLandmarks?.count ?? 0), imageSize: \(imageSize), bounds: \(bounds)")
        
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            print("❌ No graphics context!")
            return
        }
        
        print("🎨 PoseOverlayView.draw called - rect: \(rect), bounds: \(bounds)")
        
        guard let landmarks = landmarks, imageSize.width > 0, imageSize.height > 0 else {
            print("⚠️ No landmarks or invalid imageSize - landmarks: \(landmarks?.count ?? 0), imageSize: \(imageSize)")
            // Still draw target box so user knows framing
            drawTargetBox()
            return
        }
        
        print("✅ Drawing \(landmarks.count) landmarks")

        // ML Kit provides pixel coordinates; scale to view bounds
        let scaleX = bounds.width / imageSize.width
        let scaleY = bounds.height / imageSize.height

        print("📐 Scale factors - scaleX: \(scaleX), scaleY: \(scaleY)")

        // Draw target box first
        drawTargetBox()
        
        // Draw connections
        drawConnections(context: context,
                landmarks: landmarks,
                scaleX: scaleX,
                scaleY: scaleY)
        
        // Draw landmarks
        drawLandmarks(context: context,
                  landmarks: landmarks,
                  scaleX: scaleX,
                  scaleY: scaleY)
        
        // Draw countdown if active
        if isCountingDown && countdownValue > 0 {
            drawCountdown(context: context)
        } else if isPerfectPose {
            drawStatus(context: context, text: "PERFECT POSE!")
        }
    }

    private func drawTargetBox() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let insetX = bounds.width * targetBoxInsets
        let insetY = bounds.height * targetBoxInsets
        let rect = bounds.insetBy(dx: insetX, dy: insetY)

        context.saveGState()
        context.setFillColor(targetFillColor)
        context.fill(rect)

        context.setStrokeColor(targetStrokeColor)
        context.setLineWidth(3.0)
        context.setLineDash(phase: 0, lengths: [12, 6])
        context.stroke(rect)
        context.restoreGState()
    }
    
    private func drawConnections(context: CGContext, 
                                landmarks: PoseLandmarks,
                                scaleX: CGFloat,
                                scaleY: CGFloat) {
        let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist),
            (.leftShoulder, .leftHip),
            (.rightShoulder, .rightHip),
            (.leftHip, .rightHip),
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ]
        
        context.setLineWidth(4.0)
        
        for (start, end) in connections {
            // Determine line color based on accuracy
            var lineColor = UIColor.green.cgColor
            if let acc = accuracy {
                // Check if this connection is accurate
                let isAccurate: Bool
                switch (start, end) {
                case (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist):
                    isAccurate = acc.elbowAccurateLeft
                case (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist):
                    isAccurate = acc.elbowAccurateRight
                case (.leftShoulder, .leftHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle):
                    isAccurate = acc.hipAccurateLeft
                case (.rightShoulder, .rightHip), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle):
                    isAccurate = acc.hipAccurateRight
                case (.leftShoulder, .rightShoulder), (.leftHip, .rightHip):
                    isAccurate = acc.shoulderAccurateLeft && acc.shoulderAccurateRight
                default:
                    isAccurate = true
                }
                lineColor = isAccurate ? UIColor.green.cgColor : UIColor.red.cgColor
            }
            context.setStrokeColor(lineColor)
            
            guard let startPoint = landmarks[start],
                let endPoint = landmarks[end],
                startPoint.confidence > 0.3,
                endPoint.confidence > 0.3 else { continue }
            
            // ML Kit coords are in pixels; scale directly to view
            let startX = startPoint.location.x * scaleX
            let startY = startPoint.location.y * scaleY
            let endX = endPoint.location.x * scaleX
            let endY = endPoint.location.y * scaleY
            
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
        }
    }
    
    private func drawLandmarks(context: CGContext,
                              landmarks: PoseLandmarks,
                              scaleX: CGFloat,
                              scaleY: CGFloat) {
        for (joint, point) in landmarks {
            // Determine dot color based on accuracy
            var dotColor = UIColor.green.cgColor
            if let acc = accuracy {
                let isAccurate: Bool
                switch joint {
                case .leftShoulder, .leftElbow, .leftWrist:
                    isAccurate = acc.elbowAccurateLeft
                case .rightShoulder, .rightElbow, .rightWrist:
                    isAccurate = acc.elbowAccurateRight
                case .leftHip, .leftKnee, .leftAnkle:
                    isAccurate = acc.hipAccurateLeft
                case .rightHip, .rightKnee, .rightAnkle:
                    isAccurate = acc.hipAccurateRight
                default:
                    isAccurate = true
                }
                dotColor = isAccurate ? UIColor.green.cgColor : UIColor.red.cgColor
            }
            context.setFillColor(dotColor)
            
            guard point.confidence > 0.3 else { continue }
            
            // ML Kit coords are in pixels; scale directly to view
            let x = point.location.x * scaleX
            let y = point.location.y * scaleY
            
            let radius: CGFloat = 8.0
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: rect)
        }
    }
    
    private func drawCountdown(context: CGContext) {
        let text = "\(countdownValue)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 120),
            .foregroundColor: UIColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let x = (bounds.width - textSize.width) / 2
        let y = (bounds.height - textSize.height) / 2
        
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
    
    private func drawStatus(context: CGContext, text: String) {
        let statusText = text as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 50),
            .foregroundColor: UIColor.green
        ]
        
        let textSize = statusText.size(withAttributes: attributes)
        let x = (bounds.width - textSize.width) / 2
        let y: CGFloat = 100
        
        statusText.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
}
