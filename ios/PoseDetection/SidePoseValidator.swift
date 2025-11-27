import Foundation
import Vision

class SidePoseValidator {
    
    func isSidewaysPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                        tolerance: Float = 0.2) -> Bool {
        // Check if shoulders are aligned vertically (indicating sideways position)
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder] else {
            return false
        }
        
        let shoulderXDiff = abs(leftShoulder.location.x - rightShoulder.location.x)
        return shoulderXDiff < CGFloat(tolerance)
    }
    
    func areArmsSideways(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                        tolerance: Float = 0.2) -> Bool {
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder],
              let leftWrist = landmarks[.leftWrist],
              let rightWrist = landmarks[.rightWrist] else {
            return false
        }
        
        // Check if wrists are aligned with shoulders horizontally
        let leftArmXDiff = abs(leftWrist.location.x - leftShoulder.location.x)
        let rightArmXDiff = abs(rightWrist.location.x - rightShoulder.location.x)
        
        return leftArmXDiff < CGFloat(tolerance) && rightArmXDiff < CGFloat(tolerance)
    }
    
    func areLegsSideways(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                        tolerance: Float = 0.2) -> Bool {
        guard let leftHip = landmarks[.leftHip],
              let rightHip = landmarks[.rightHip],
              let leftAnkle = landmarks[.leftAnkle],
              let rightAnkle = landmarks[.rightAnkle] else {
            return false
        }
        
        // Check if ankles are aligned with hips horizontally
        let leftLegXDiff = abs(leftAnkle.location.x - leftHip.location.x)
        let rightLegXDiff = abs(rightAnkle.location.x - rightHip.location.x)
        
        return leftLegXDiff < CGFloat(tolerance) && rightLegXDiff < CGFloat(tolerance)
    }
    
    func isValidSidePose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        return isSidewaysPose(landmarks) &&
               areArmsSideways(landmarks) &&
               areLegsSideways(landmarks)
    }
}
