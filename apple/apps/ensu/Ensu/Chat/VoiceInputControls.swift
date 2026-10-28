import SwiftUI

struct VoiceInputControls: View {
    @ObservedObject var service: VoiceTranscriptionService
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        switch service.state {
        case .downloading: return "Downloading"
        case .preparing: return "Preparing"
        case .transcribing: return "Transcribing"
        case .recording: return service.snapshot?.phase == .countdown ? "Finishing" : "Listening"
        case .error(let message):
            if message.contains("permission") { return "Microphone access" }
            return message == "No speech detected." ? "No speech" : "Stopped"
        case .idle: return "Preparing"
        }
    }

    var body: some View {
        if service.active || service.state.isError {
            HStack(spacing: 12) {
                Text(status).font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
                    .accessibilityHint(service.notice ?? "")
                    .onTapGesture {
                        if case .error(let message) = service.state,
                            message.contains("permission"),
                            let url = URL(string: UIApplication.openSettingsURLString)
                        {
                            openURL(url)
                        }
                    }
                if service.state.isRecording {
                    waveform.frame(height: 24)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 0) {
                ForEach(service.audioLevels.indices, id: \.self) { index in
                    let level = service.audioLevels[index]
                    Capsule()
                        .fill(EnsuColor.textPrimary.opacity(0.35 + Double(level) * 0.65))
                        .frame(
                            width: min(3, geometry.size.width / 48), height: 3 + CGFloat(level) * 21
                        )
                        .frame(
                            width: geometry.size.width / CGFloat(service.audioLevels.count),
                            height: 24)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: service.audioLevels)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone activity")
    }
}

struct VoiceInputButton: View {
    @ObservedObject var service: VoiceTranscriptionService
    let enabled: Bool
    let onOpen: () -> Void

    private var canPress: Bool {
        service.active ? service.state.isRecording : enabled && !service.hasActiveTasks
    }

    private var label: String {
        switch service.state {
        case .downloading: return "Downloading voice model"
        case .preparing: return "Preparing voice input"
        case .transcribing: return "Transcribing"
        case .recording: return "Stop dictation"
        case .idle, .error: return "Dictate"
        }
    }

    var body: some View {
        Button {
            if service.state.isRecording { service.stop() } else { onOpen() }
        } label: {
            ZStack {
                switch service.state {
                case .downloading(let percent):
                    if let percent {
                        Circle().stroke(EnsuColor.textMuted.opacity(0.2), lineWidth: 2)
                        Circle().trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                            .stroke(
                                EnsuColor.textPrimary,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
                case .preparing, .transcribing:
                    ProgressView().controlSize(.small)
                case .recording:
                    Circle().fill(EnsuColor.textPrimary).frame(width: 32, height: 32)
                    RoundedRectangle(cornerRadius: 2).fill(EnsuColor.backgroundBase)
                        .frame(width: 12, height: 12)
                case .idle, .error:
                    Image("Mic02Icon").resizable().scaledToFit().frame(width: 20, height: 20)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .foregroundStyle(canPress ? EnsuColor.textPrimary : EnsuColor.textMuted)
        .disabled(!canPress)
        .accessibilityLabel(label)
    }
}
