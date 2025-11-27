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
        
        // Ensure on main thread for speech
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.synthesizer.stopSpeaking(at: .immediate)
            
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            
            self.synthesizer.speak(utterance)
            
            self.lastSpokenMessage = message
            self.lastSpeakTime = currentTime
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
