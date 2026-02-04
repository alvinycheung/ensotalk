import Foundation
import AVFoundation
import SwiftUI
import Accelerate

enum ChatState {
    case idle
    case listening      // Always-on mode, waiting for voice
    case recording
    case transcribing
    case thinking
    case speaking
}

enum ListenMode: String, CaseIterable {
    case pushToTalk = "Push to Talk"
    case alwaysListening = "Always Listening"
}

@MainActor
class ChatManager: NSObject, ObservableObject {
    @Published var state: ChatState = .idle
    @Published var transcript: String = ""
    @Published var response: String = ""
    @Published var error: String?
    @Published var listenMode: ListenMode = .pushToTalk
    @Published var audioLevel: Float = 0
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingURL: URL?
    private var silenceTimer: Timer?
    private var levelTimer: Timer?
    private var isVoiceDetected = false
    private var voiceStartTime: Date?
    
    // VAD settings
    private let silenceThreshold: Float = -40  // dB threshold for silence
    private let silenceDuration: TimeInterval = 1.5  // seconds of silence to end recording
    private let minRecordingDuration: TimeInterval = 0.5  // minimum recording length
    
    private let openClawURL = "http://127.0.0.1:18789"
    private var openClawToken: String?
    private var whisperAPIKey: String?
    private var openAIAPIKey: String?
    
    override init() {
        super.init()
        loadConfig()
    }
    
    private func loadConfig() {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/openclaw.json")
        
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = "Could not load OpenClaw config"
            return
        }
        
        if let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            openClawToken = token
        }
        
        if let skills = json["skills"] as? [String: Any],
           let entries = skills["entries"] as? [String: Any],
           let whisper = entries["openai-whisper-api"] as? [String: Any],
           let key = whisper["apiKey"] as? String {
            whisperAPIKey = key
        }
        
        openAIAPIKey = whisperAPIKey
    }
    
    func setListenMode(_ mode: ListenMode) {
        listenMode = mode
        if mode == .alwaysListening {
            startAlwaysListening()
        } else {
            stopAlwaysListening()
        }
    }
    
    func startAlwaysListening() {
        guard state == .idle || state == .listening else { return }
        state = .listening
        startListeningForVoice()
    }
    
    func stopAlwaysListening() {
        silenceTimer?.invalidate()
        levelTimer?.invalidate()
        audioRecorder?.stop()
        audioRecorder = nil
        if state == .listening || state == .recording {
            state = .idle
        }
    }
    
    private func startListeningForVoice() {
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("ensotalk_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isVoiceDetected = false
            voiceStartTime = nil
            
            // Monitor audio levels
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkAudioLevel()
                }
            }
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
        }
    }
    
    private func checkAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        audioLevel = level
        
        let isSpeaking = level > silenceThreshold
        
        if isSpeaking && !isVoiceDetected {
            // Voice started
            isVoiceDetected = true
            voiceStartTime = Date()
            state = .recording
            silenceTimer?.invalidate()
        } else if !isSpeaking && isVoiceDetected {
            // Potential end of speech - start silence timer
            if silenceTimer == nil {
                silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.endVoiceCapture()
                    }
                }
            }
        } else if isSpeaking && isVoiceDetected {
            // Still speaking - cancel silence timer
            silenceTimer?.invalidate()
            silenceTimer = nil
        }
    }
    
    private func endVoiceCapture() {
        guard isVoiceDetected,
              let startTime = voiceStartTime,
              Date().timeIntervalSince(startTime) >= minRecordingDuration else {
            // Too short, reset
            isVoiceDetected = false
            voiceStartTime = nil
            silenceTimer = nil
            state = .listening
            return
        }
        
        levelTimer?.invalidate()
        audioRecorder?.stop()
        state = .transcribing
        
        Task {
            await processRecording()
            
            // Resume listening if in always-listening mode
            if listenMode == .alwaysListening && state == .idle {
                state = .listening
                startListeningForVoice()
            }
        }
    }
    
    func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .listening:
            // In always-listening mode, manual trigger forces end
            if isVoiceDetected {
                endVoiceCapture()
            }
        default:
            break
        }
    }
    
    private func startRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("ensotalk_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()
            state = .recording
            transcript = ""
            response = ""
            error = nil
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        state = .transcribing
        
        Task {
            await processRecording()
        }
    }
    
    private func processRecording() async {
        guard let url = recordingURL else { return }
        
        do {
            let text = try await transcribeAudio(url: url)
            transcript = text
            
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                return
            }
            
            state = .thinking
            let reply = try await sendToOpenClaw(message: text)
            response = reply
            
            state = .speaking
            try await speakResponse(text: reply)
            
            state = .idle
        } catch {
            self.error = error.localizedDescription
            state = .idle
        }
        
        try? FileManager.default.removeItem(at: url)
        isVoiceDetected = false
        voiceStartTime = nil
        silenceTimer = nil
    }
    
    private func transcribeAudio(url: URL) async throws -> String {
        guard let apiKey = whisperAPIKey else {
            throw NSError(domain: "EnsoTalk", code: 1, userInfo: [NSLocalizedDescriptionKey: "Whisper API key not configured"])
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let audioData = try Data(contentsOf: url)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let text = json?["text"] as? String else {
            throw NSError(domain: "EnsoTalk", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to transcribe audio"])
        }
        
        return text
    }
    
    private func sendToOpenClaw(message: String) async throws -> String {
        guard let token = openClawToken else {
            throw NSError(domain: "EnsoTalk", code: 3, userInfo: [NSLocalizedDescriptionKey: "OpenClaw token not configured"])
        }
        
        var request = URLRequest(url: URL(string: "\(openClawURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("main", forHTTPHeaderField: "x-openclaw-agent-id")
        
        let payload: [String: Any] = [
            "model": "openclaw",
            "messages": [
                ["role": "user", "content": message]
            ],
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let messageObj = first["message"] as? [String: Any],
              let content = messageObj["content"] as? String else {
            throw NSError(domain: "EnsoTalk", code: 4, userInfo: [NSLocalizedDescriptionKey: "No reply from OpenClaw"])
        }
        
        return content
    }
    
    private func speakResponse(text: String) async throws {
        guard let apiKey = openAIAPIKey else {
            let synth = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            synth.speak(utterance)
            while synth.isSpeaking {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return
        }
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let payload: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": "nova",
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "EnsoTalk", code: 5, userInfo: [NSLocalizedDescriptionKey: "TTS failed: \(errorMsg)"])
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("response.mp3")
        try data.write(to: tempURL)
        
        audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
        audioPlayer?.play()
        
        while audioPlayer?.isPlaying == true {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        try? FileManager.default.removeItem(at: tempURL)
    }
}
