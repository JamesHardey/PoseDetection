import Foundation
import Vision

class PoseValidator {
    // Posture metrics matching Android implementation
    struct PostureMetrics {
        let shoulderAngleLeft: Double
        let shoulderAngleRight: Double
        let elbowAngleLeft: Double
        let elbowAngleRight: Double
        let spineAngle: Double
        let hipAngleLeft: Double
        let hipAngleRight: Double
        let shoulderLevelDiff: Double
        let legSeparationAngle: Double
    }
    
    // Reference pose values matching Android
    struct ReferencePose {
        let shoulderAngle: Double = 160.0
        let elbowAngle: Double = 180.0
        let spineAngle: Double = 10.0
        let hipAngle: Double = 180.0
        let tolerance: Double = 30.0  // Increased tolerance for better detection
    }
    
    let referencePose = ReferencePose()
    
    // Calculate angle between three points (matching Android's calculateAngle)
    private func calculateAngle(first: CGPoint, mid: CGPoint, last: CGPoint) -> Double {
        let radians = atan2(last.y - mid.y, last.x - mid.x) -
                     atan2(first.y - mid.y, first.x - mid.x)
        
        var angle = abs(radians * 180.0 / .pi)
        
        if angle > 180.0 {
            angle = 360.0 - angle
        }
        
        return angle
    }
    
    func isValidPose(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], 
                     confidenceThreshold: Float = 0.5) -> Bool {
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
    
    // Calculate posture metrics (matching Android implementation)
    func calculatePostureMetrics(_ landmarks: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> PostureMetrics? {
        guard let leftShoulder = landmarks[.leftShoulder],
              let rightShoulder = landmarks[.rightShoulder],
              let leftElbow = landmarks[.leftElbow],
              let rightElbow = landmarks[.rightElbow],
              let leftWrist = landmarks[.leftWrist],
              let rightWrist = landmarks[.rightWrist],
              let leftHip = landmarks[.leftHip],
              let rightHip = landmarks[.rightHip],
              let leftKnee = landmarks[.leftKnee],
              let rightKnee = landmarks[.rightKnee],
              let neck = landmarks[.neck] else {
            return nil
        }
        
        // Calculate angles matching Android implementation
        let shoulderAngleLeft = calculateAngle(
            first: leftElbow.location,
            mid: leftShoulder.location,
            last: leftHip.location
        )
        let shoulderAngleRight = calculateAngle(
            first: rightElbow.location,
            mid: rightShoulder.location,
            last: rightHip.location
        )
        let elbowAngleLeft = calculateAngle(
            first: leftShoulder.location,
            mid: leftElbow.location,
            last: leftWrist.location
        )
        let elbowAngleRight = calculateAngle(
            first: rightShoulder.location,
            mid: rightElbow.location,
            last: rightWrist.location
        )
        
        // Calculate spine angle (neck to hip center)
        let hipCenter = CGPoint(
            x: (leftHip.location.x + rightHip.location.x) / 2,
            y: (leftHip.location.y + rightHip.location.y) / 2
        )
        let spineAngle = abs(atan2(hipCenter.y - neck.location.y, hipCenter.x - neck.location.x) * 180.0 / .pi)
        
        // Hip angles
        let hipAngleLeft = calculateAngle(
            first: leftShoulder.location,
            mid: leftHip.location,
            last: leftKnee.location
        )
        let hipAngleRight = calculateAngle(
            first: rightShoulder.location,
            mid: rightHip.location,
            last: rightKnee.location
        )
        
        // Shoulder level difference
        let shoulderLevelDiff = abs(leftShoulder.location.y - rightShoulder.location.y)
        
        // Leg separation angle
        let legSeparationAngle = calculateAngle(
            first: leftKnee.location,
            mid: hipCenter,
            last: rightKnee.location
        )
        
        return PostureMetrics(
            shoulderAngleLeft: shoulderAngleLeft,
            shoulderAngleRight: shoulderAngleRight,
            elbowAngleLeft: elbowAngleLeft,
            elbowAngleRight: elbowAngleRight,
            spineAngle: spineAngle,
            hipAngleLeft: hipAngleLeft,
            hipAngleRight: hipAngleRight,
            shoulderLevelDiff: Double(shoulderLevelDiff),
            legSeparationAngle: legSeparationAngle
        )
    }
    
    // Compare with reference pose (matching Android's compareWithReference)
    func isPoseAccurate(_ metrics: PostureMetrics) -> Bool {
        let shouldersLevel = abs(metrics.shoulderAngleLeft - referencePose.shoulderAngle) < referencePose.tolerance &&
                            abs(metrics.shoulderAngleRight - referencePose.shoulderAngle) < referencePose.tolerance

        let armsRelaxed = abs(metrics.elbowAngleLeft - referencePose.elbowAngle) < referencePose.tolerance &&
                         abs(metrics.elbowAngleRight - referencePose.elbowAngle) < referencePose.tolerance

        let spineErect = metrics.spineAngle < referencePose.spineAngle + referencePose.tolerance

        let hipsLevel = abs(metrics.hipAngleLeft - referencePose.hipAngle) < referencePose.tolerance &&
                       abs(metrics.hipAngleRight - referencePose.hipAngle) < referencePose.tolerance

        // Debug logging
        print("📊 Pose Metrics:")
        print("  Shoulders: L=\(String(format: \"%.1f\", metrics.shoulderAngleLeft))° R=\(String(format: \"%.1f\", metrics.shoulderAngleRight))° (target: \(referencePose.shoulderAngle)° ± \(referencePose.tolerance)°)")
        print("  Elbows: L=\(String(format: \"%.1f\", metrics.elbowAngleLeft))° R=\(String(format: \"%.1f\", metrics.elbowAngleRight))° (target: \(referencePose.elbowAngle)° ± \(referencePose.tolerance)°)")
        print("  Spine: \(String(format: \"%.1f\", metrics.spineAngle))° (max: \(referencePose.spineAngle + referencePose.tolerance)°)")
        print("  Hips: L=\(String(format: \"%.1f\", metrics.hipAngleLeft))° R=\(String(format: \"%.1f\", metrics.hipAngleRight))° (target: \(referencePose.hipAngle)° ± \(referencePose.tolerance)°)")
        print("✅ Checks: Shoulders=\(shouldersLevel), Arms=\(armsRelaxed), Spine=\(spineErect), Hips=\(hipsLevel)")

        return shouldersLevel && armsRelaxed && spineErect && hipsLevel
    }
    
    // Legacy helper methods for backward compatibility
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
