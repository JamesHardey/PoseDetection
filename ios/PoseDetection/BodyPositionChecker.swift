import Foundation
import Vision

class BodyPositionChecker {
    private let poseValidator = PoseValidator()
    
    func checkPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> (isValid: Bool, feedback: String) {
        // First check if basic pose is valid
        if !poseValidator.isValidPose(landmarks) {
            return (false, "Cannot detect full body. Please ensure you're fully visible in frame.")
        }
        
        // Calculate posture metrics using Android-style angle calculations
        guard let metrics = poseValidator.calculatePostureMetrics(landmarks) else {
            return (false, "Cannot calculate posture metrics")
        }
        
        // Check if pose is accurate compared to reference
        if !poseValidator.isPoseAccurate(metrics) {
            // Provide specific feedback based on metrics
            let reference = poseValidator.referencePose
            
            // Check shoulders
            if abs(metrics.shoulderAngleLeft - reference.shoulderAngle) >= reference.tolerance ||
               abs(metrics.shoulderAngleRight - reference.shoulderAngle) >= reference.tolerance {
                return (false, "Keep your shoulders level and relaxed")
            }
            
            // Check arms
            if abs(metrics.elbowAngleLeft - reference.elbowAngle) >= reference.tolerance ||
               abs(metrics.elbowAngleRight - reference.elbowAngle) >= reference.tolerance {
                return (false, "Put your arms straight down by your sides")
            }
            
            // Check spine
            if metrics.spineAngle >= reference.spineAngle + reference.tolerance {
                return (false, "Stand up straight")
            }
            
            // Check hips
            if abs(metrics.hipAngleLeft - reference.hipAngle) >= reference.tolerance ||
               abs(metrics.hipAngleRight - reference.hipAngle) >= reference.tolerance {
                return (false, "Keep your legs straight")
            }
            
            return (false, "Adjust your posture")
        }
        
        // Check body centered (legacy helper)
        if !poseValidator.isBodyCentered(landmarks) {
            return (false, "Move to center of frame")
        }
        
        // Check feet apart (legacy helper)
        if !poseValidator.areFeetApart(landmarks) {
            return (false, "Spread your feet shoulder-width apart")
        }
        
        return (true, "Perfect! Hold still...")
    }
}
