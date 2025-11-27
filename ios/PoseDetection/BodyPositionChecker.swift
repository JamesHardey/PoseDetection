import Foundation
import Vision

class BodyPositionChecker {
    private let poseValidator = PoseValidator()
    
    func checkPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> (isValid: Bool, feedback: String) {
        // First check if basic pose is valid
        if !poseValidator.isValidPose(landmarks) {
            return (false, "Cannot detect full body. Please ensure you're fully visible in frame.")
        }
        
        // Check shoulders level
        if !poseValidator.areShouldersLevel(landmarks) {
            return (false, "Keep your shoulders level")
        }
        
        // Check arms down
        if !poseValidator.areArmsDown(landmarks) {
            return (false, "Put your arms down by your sides")
        }
        
        // Check feet apart
        if !poseValidator.areFeetApart(landmarks) {
            return (false, "Spread your feet shoulder-width apart")
        }
        
        // Check body centered
        if !poseValidator.isBodyCentered(landmarks) {
            return (false, "Move to center of frame")
        }
        
        return (true, "Perfect! Hold still...")
    }
}
