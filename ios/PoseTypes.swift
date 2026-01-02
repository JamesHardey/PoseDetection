import CoreGraphics
import Vision

// Common point type used across overlay and validators when not using Vision's VNRecognizedPoint directly
public struct RecognizedPointCompat {
    public let location: CGPoint
    public let confidence: Float
}

// Reuse Vision joint names for keys
public typealias JointName = VNHumanBodyPoseObservation.JointName
public typealias PoseLandmarks = [JointName: RecognizedPointCompat]
