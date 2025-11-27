import AVFoundation

class VoiceFeedbackProvider {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenMessage: String = ""
    private var lastSpeakTime: Date = Date.distantPast
    private let minimumSpeakInterval: TimeInterval = 2.0
    
    func provideFeedback(_ message: String) {
        // Avoid repeating the same message too frequently
        let currentTime = Date()
        if message == lastSpokenMessage && 
           currentTime.timeIntervalSince(lastSpeakTime) < minimumSpeakInterval {
            return
        }
        
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
        
        lastSpokenMessage = message
        lastSpeakTime = currentTime
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
