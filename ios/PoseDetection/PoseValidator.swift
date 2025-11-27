import Foundation
import Vision

class PoseValidator {
    // Landmark indices based on Vision framework
    private enum LandmarkIndex: Int {
        case nose = 0
        case leftEye = 1
        case rightEye = 2
        case leftEar = 3
        case rightEar = 4
        case leftShoulder = 5
        case rightShoulder = 6
        case leftElbow = 7
        case rightElbow = 8
        case leftWrist = 9
        case rightWrist = 10
        case leftHip = 11
        case rightHip = 12
        case leftKnee = 13
        case rightKnee = 14
        case leftAnkle = 15
        case rightAnkle = 16
    }
    
    func isValidPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                     confidenceThreshold: Float = 0.5) -> Bool {
        // Check if all critical landmarks are present with sufficient confidence
        let criticalLandmarks: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]
        
        for landmark in criticalLandmarks {
            guard let point = landmarks[landmark],
                  point.confidence > confidenceThreshold else {
                return false
            }
        }
        
        return true
    }
    
    func areShouldersLevel(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                          tolerance: Float = 0.15) -> Bool {
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder] else {
            return false
        }
        
        let yDifference = abs(leftShoulder.location.y - rightShoulder.location.y)
        return yDifference < CGFloat(tolerance)
    }
    
    func areArmsDown(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                    tolerance: Float = 0.2) -> Bool {
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder],
              let leftWrist = landmarks[.leftWrist],
              let rightWrist = landmarks[.rightWrist] else {
            return false
        }
        
        // Wrists should be below shoulders
        let leftArmDown = leftWrist.location.y < leftShoulder.location.y - CGFloat(tolerance)
        let rightArmDown = rightWrist.location.y < rightShoulder.location.y - CGFloat(tolerance)
        
        return leftArmDown && rightArmDown
    }
    
    func areFeetApart(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                     minDistance: Float = 0.15) -> Bool {
        guard let leftAnkle = landmarks[.leftAnkle],
              let rightAnkle = landmarks[.rightAnkle] else {
            return false
        }
        
        let distance = abs(leftAnkle.location.x - rightAnkle.location.x)
        return distance >= CGFloat(minDistance)
    }
    
    func isBodyCentered(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                       centerTolerance: Float = 0.2) -> Bool {
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder] else {
            return false
        }
        
        let shoulderCenter = (leftShoulder.location.x + rightShoulder.location.x) / 2
        let screenCenter: CGFloat = 0.5
        
        let distanceFromCenter = abs(shoulderCenter - screenCenter)
        return distanceFromCenter < CGFloat(centerTolerance)
    }
}
