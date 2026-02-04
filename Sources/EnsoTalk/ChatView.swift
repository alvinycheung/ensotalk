import SwiftUI

struct ChatView: View {
    @ObservedObject var manager: ChatManager
    
    var body: some View {
        VStack(spacing: 12) {
            // Mode selector
            Picker("Mode", selection: $manager.listenMode) {
                ForEach(ListenMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: manager.listenMode) { _, newValue in
                manager.setListenMode(newValue)
            }
            
            Divider()
            
            // Status indicator with audio level
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusText)
                    .font(.headline)
                Spacer()
                
                // Audio level meter (only in listening/recording)
                if manager.state == .listening || manager.state == .recording {
                    AudioLevelView(level: manager.audioLevel)
                        .frame(width: 60, height: 16)
                }
            }
            
            // Transcript
            if !manager.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(manager.transcript)
                        .font(.body)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Response
            if !manager.response.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enso:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(manager.response)
                        .font(.body)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Error
            if let error = manager.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Instructions + Quit
            HStack {
                Text(instructionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 320, height: 240)
    }
    
    var statusColor: Color {
        switch manager.state {
        case .idle: return .gray
        case .listening: return .blue
        case .recording: return .red
        case .transcribing: return .orange
        case .thinking: return .yellow
        case .speaking: return .green
        }
    }
    
    var statusText: String {
        switch manager.state {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }
    
    var instructionText: String {
        switch manager.listenMode {
        case .pushToTalk:
            return "⌥ Space to talk"
        case .alwaysListening:
            return "Just speak — I'm listening"
        }
    }
}

struct AudioLevelView: View {
    let level: Float  // dB, typically -160 to 0
    
    var body: some View {
        GeometryReader { geometry in
            let normalizedLevel = max(0, min(1, (level + 60) / 60))  // -60dB to 0dB range
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor(normalizedLevel))
                    .frame(width: geometry.size.width * CGFloat(normalizedLevel))
            }
        }
    }
    
    func levelColor(_ level: Float) -> Color {
        if level > 0.8 {
            return .red
        } else if level > 0.5 {
            return .orange
        } else {
            return .green
        }
    }
}
