import SwiftUI
import AVFoundation
import Speech

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var status = "Ready when you are"
    @Published var preparing = false
    private let engine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var sessionID: UUID?

    func start(locale: String) async {
        guard !recording, !preparing else { return }
        preparing = true
        defer { preparing = false }
        let speechAllowed: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled else { return }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard !Task.isCancelled else { return }
        guard speechAllowed == .authorized, microphoneAllowed else { status = "Allow microphone and speech recognition in iPhone Settings to record."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else { status = "Speech recognition is unavailable for this language or connection."; return }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request
            let sessionID = UUID()
            self.sessionID = sessionID
            transcript = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain: "Voice", code: 1, userInfo: [NSLocalizedDescriptionKey: "The microphone is unavailable."]) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true || error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == sessionID else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop(); self.status = error?.localizedDescription ?? "Transcript ready" }
                }
            }
            engine.prepare(); try engine.start(); recording = true
            status = recognizer.supportsOnDeviceRecognition ? "Listening on this device…" : "Listening with Apple's speech service…"
        } catch { stop(); status = error.localizedDescription }
    }

    func stop() {
        sessionID = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognitionTask?.cancel()
        recognitionTask = nil; request = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status = transcript.isEmpty ? "Ready when you are" : "Transcript ready"
    }
}

struct VoiceView: View {
    @StateObject private var recorder = VoiceRecorder()
    @State private var locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    @State private var permissionTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    /// Every language Apple's speech recognition offers on this device, by name.
    private var locales: [(String, String)] {
        SFSpeechRecognizer.supportedLocales()
            .map { ($0.identifier.replacingOccurrences(of: "_", with: "-"), Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recorder.recording ? "waveform" : "mic.circle.fill")
                .font(.system(size: 62)).foregroundStyle(.mint).padding(.top, 22)
            Text(recorder.status).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Picker("Speech language", selection: $locale) { ForEach(locales, id: \.0) { code, name in Text(name).tag(code) } }.disabled(recorder.recording || recorder.preparing)
            TextEditor(text: $recorder.transcript).scrollContentBackground(.hidden).padding(10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Voice transcript")
            HStack(spacing: 12) {
                Button(recorder.recording ? "Stop recording" : "Start recording", systemImage: recorder.recording ? "stop.fill" : "mic.fill") {
                    if recorder.recording { recorder.stop() }
                    else { permissionTask = Task { await recorder.start(locale: locale) } }
                }.buttonStyle(.borderedProminent).disabled(recorder.preparing)
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = recorder.transcript; recorder.status = "Copied. Return to your message and paste." }
                    .buttonStyle(.bordered).disabled(recorder.transcript.isEmpty)
            }
            Text("Recording runs only while this screen is active. Only languages Apple's speech recognition supports are listed. For Pidgin, choose English (Nigeria).")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(22).background(Color(red: 0.035, green: 0.10, blue: 0.13)).navigationTitle("Voice editor").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !locales.contains(where: { $0.0 == locale }) else { return }
                // Fall back to another variety of the phone's language, then to the first available language.
                let language = Locale.current.language.languageCode?.identifier ?? "en"
                locale = locales.first { $0.0.hasPrefix(language + "-") }?.0 ?? locales.first?.0 ?? "en-US"
            }
            .onDisappear { permissionTask?.cancel(); recorder.stop() }
            .onChange(of: phase) { _, phase in
                if phase == .background || (phase == .inactive && recorder.recording) {
                    permissionTask?.cancel(); recorder.stop()
                }
            }
    }
}
