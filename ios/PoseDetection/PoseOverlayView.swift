import UIKit
import Vision

class PoseOverlayView: UIView {
    private var landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?
    private var imageSize: CGSize = .zero
    private var isPerfectPose: Bool = false
    private var countdownValue: Int = 0
    private var isCountingDown: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePose(_ newLandmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?, 
                    imageSize: CGSize,
                    perfect: Bool = false,
                    countdown: Int = 0,
                    counting: Bool = false) {
        self.landmarks = newLandmarks
        self.imageSize = imageSize
        self.isPerfectPose = perfect
        self.countdownValue = countdown
        self.isCountingDown = counting
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        guard let landmarks = landmarks, imageSize.width > 0, imageSize.height > 0 else { return }
        
        let scaleX = bounds.width / imageSize.width
        let scaleY = bounds.height / imageSize.height
        
        // Draw connections
        drawConnections(context: context, landmarks: landmarks, scaleX: scaleX, scaleY: scaleY)
        
        // Draw landmarks
        drawLandmarks(context: context, landmarks: landmarks, scaleX: scaleX, scaleY: scaleY)
        
        // Draw countdown if active
        if isCountingDown && countdownValue > 0 {
            drawCountdown(context: context)
        } else if isPerfectPose {
            drawStatus(context: context, text: "PERFECT POSE!")
        }
    }
    
    private func drawConnections(context: CGContext, 
                                landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
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
        
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(4.0)
        
        for (start, end) in connections {
            guard let startPoint = landmarks[start],
                  let endPoint = landmarks[end],
                  startPoint.confidence > 0.3,
                  endPoint.confidence > 0.3 else { continue }
            
            let startX = startPoint.location.x * scaleX
            let startY = (1 - startPoint.location.y) * scaleY
            let endX = endPoint.location.x * scaleX
            let endY = (1 - endPoint.location.y) * scaleY
            
            context.move(to: CGPoint(x: startX, y: startY))
            context.addLine(to: CGPoint(x: endX, y: endY))
            context.strokePath()
        }
    }
    
    private func drawLandmarks(context: CGContext,
                              landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                              scaleX: CGFloat,
                              scaleY: CGFloat) {
        context.setFillColor(UIColor.green.cgColor)
        
        for (_, point) in landmarks {
            guard point.confidence > 0.3 else { continue }
            
            let x = point.location.x * scaleX
            let y = (1 - point.location.y) * scaleY
            
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
