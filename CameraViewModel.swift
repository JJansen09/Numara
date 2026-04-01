import AVFoundation
import UIKit
import SwiftUI
import Speech
import AudioToolbox
import MediaPlayer

@MainActor
class CameraViewModel: NSObject, ObservableObject {

    // MARK: - State
    enum AppState {
        case capture               // home — viewfinder
        case processing            // spinner — waiting on Claude
        case result(NumaraResult)  // showing result
        case listening             // "hey numara" wake state
        case voiceCalc             // voice calculator mode — always listening
        case calcResult(CalcResult) // showing calc answer
        case error(String)
    }

    enum ContentType {
        case price
        case equation
        case receipt
        case unknown
    }

    struct NumaraResult {
        let image: UIImage
        let rawText: String
        let type: ContentType
        let scannedText: String
    }

    struct CalcResult {
        let equation: String   // "15 + 8 = 23" — shown large on screen
        let answer: String     // spoken response with anchor
        let isSolveMode: Bool
    }

    @Published var state: AppState = .capture
    @Published var isListening = false

    // MARK: - Camera
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?

    // MARK: - Speech
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Config
    var apiKey: String = ""  // set from app entry point / keychain in prod

    // MARK: - Setup
    override init() {
        super.init()
        setupCamera()
        setupRemoteCommands()
    }

    // MARK: - Ray-Ban temple tap (single tap = play/pause over Bluetooth)
    // iOS receives the glasses tap as MPRemoteCommandCenter playback event.
    // We hijack it: if Numara is foreground, tap triggers listening.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        UIApplication.shared.beginReceivingRemoteControlEvents()

        // Single tap on Ray-Ban temple fires togglePlayPause.
        // play/pause handlers catch other Bluetooth headset button styles.
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            Task { @MainActor in self.handleTap() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            Task { @MainActor in self.handleTap() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            Task { @MainActor in self.handleTap() }
            return .success
        }

        // Publish a minimal Now Playing entry so iOS keeps Numara as the
        // active remote target even when no audio is currently playing
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "numara",
            MPMediaItemPropertyArtist: "listening assistant"
        ]
    }

    // Decides what a temple tap means based on current screen
    private func handleTap() {
        switch state {
        case .result(let result):
            startListening(onResult: result)   // open follow-up listening
        case .listening:
            stopListening()                    // cancel listening early
        case .capture:
            capturePhoto()                     // shutter — phone stays in pocket
        default:
            break
        }
    }

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()

        Task.detached { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Capture
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Analyze
    func analyze(image: UIImage) async {
        state = .processing

        do {
            let response = try await ClaudeService.analyze(image: image, apiKey: apiKey)
            let type = detectType(from: response)
            let scanned = extractScannedText(from: response)

            let result = NumaraResult(
                image: image,
                rawText: response,
                type: type,
                scannedText: scanned
            )
            state = .result(result)
            speak(response)

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Follow-up voice question
    func askFollowUp(question: String, result: NumaraResult) async {
        state = .processing
        do {
            let response = try await ClaudeService.followUp(
                image: result.image,
                priorResponse: result.rawText,
                question: question,
                apiKey: apiKey
            )
            let updated = NumaraResult(
                image: result.image,
                rawText: response,
                type: result.type,
                scannedText: result.scannedText
            )
            state = .result(updated)
            speak(response)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Speech output
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48          // slightly slower — comfortable for processing
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    // MARK: - Chime (silence timeout with nothing said)
    func playChime() {
        // Soft system sound — routes through active audio output (glasses speakers when BT connected)
        AudioServicesPlaySystemSound(1057)
    }

    // MARK: - Voice calculator
    // Enters always-listening calc mode from the voice tab
    func enterVoiceCalc() {
        state = .voiceCalc
        startCalcListening()
    }

    func startCalcListening() {
        guard !audioEngine.isRunning else { return }
        isListening = true

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            Task { @MainActor in self.beginCalcRecognition() }
        }
    }

    // Detects "calculate" or "solve" as trigger for solver mode
    // Everything else goes through general anchor mode
    private func isSolveMode(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("calculate") || lower.contains("solve") ||
               lower.contains("times") || lower.contains("multiply") ||
               lower.contains("divided") || lower.contains("divide")
    }

    private func beginCalcRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        var silenceTimer: Timer?
        var lastTranscript = ""

        func resetSilenceTimer() {
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                let cleaned = lastTranscript
                    .replacingOccurrences(of: "hey numara", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if cleaned.isEmpty {
                    // Nothing said — chime, stay in calc mode ready for next question
                    self.playChime()
                    Task { @MainActor in
                        self.audioEngine.stop()
                        self.audioEngine.inputNode.removeTap(onBus: 0)
                        self.isListening = false
                        // Re-enter listening after short pause
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.startCalcListening()
                    }
                } else {
                    // Fire the question
                    let solveMode = self.isSolveMode(cleaned)
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.isListening = false
                    Task { await self.processCalcQuestion(cleaned, isSolveMode: solveMode) }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let spoken = result.bestTranscription.formattedString.lowercased()
                if spoken != lastTranscript {
                    lastTranscript = spoken
                    resetSilenceTimer()
                }
                let cleaned = spoken
                    .replacingOccurrences(of: "hey numara", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if result.isFinal && !cleaned.isEmpty {
                    silenceTimer?.invalidate()
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    self.isListening = false
                    let solveMode = self.isSolveMode(cleaned)
                    Task { await self.processCalcQuestion(cleaned, isSolveMode: solveMode) }
                }
            }
            if error != nil {
                silenceTimer?.invalidate()
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.isListening = false
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        try? audioEngine.start()
        resetSilenceTimer()
    }

    private func processCalcQuestion(_ question: String, isSolveMode: Bool) async {
        await MainActor.run { state = .processing }

        do {
            let result = try await ClaudeService.voiceCalculate(
                question: question,
                isSolveMode: isSolveMode,
                apiKey: apiKey
            )
            let calcResult = CalcResult(
                equation: result.equation,
                answer: result.answer,
                isSolveMode: isSolveMode
            )
            await MainActor.run {
                state = .calcResult(calcResult)
                speak(result.answer)
            }
            // After speaking, re-enter listening — no wake word needed
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { startCalcListening() }

        } catch {
            await MainActor.run { state = .error(error.localizedDescription) }
        }
    }

    // MARK: - Speech recognition (wake word: "hey numara")
    func startListening(onResult: NumaraResult) {
        guard !audioEngine.isRunning else { return }
        isListening = true
        state = .listening

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            Task { @MainActor in
                self.beginRecognition(onResult: onResult)
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isListening = false
    }

    private func beginRecognition(onResult: NumaraResult) {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        // Silence timeout — fires if no new transcript after 3 seconds
        var silenceTimer: Timer?
        var lastTranscript = ""

        func resetSilenceTimer() {
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                let cleaned = lastTranscript
                    .replacingOccurrences(of: "hey numara", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                self.stopListening()

                if cleaned.isEmpty {
                    // Nothing useful said — chime and return to result
                    self.playChime()
                    Task { @MainActor in self.state = .result(onResult) }
                } else {
                    // Something was said — fire it as a question
                    Task { await self.askFollowUp(question: cleaned, result: onResult) }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let spoken = result.bestTranscription.formattedString.lowercased()
                // Only reset timer when transcript actually changes
                if spoken != lastTranscript {
                    lastTranscript = spoken
                    resetSilenceTimer()
                }
                // Also handle isFinal from the recognizer itself
                let cleaned = spoken
                    .replacingOccurrences(of: "hey numara", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isFinal && !cleaned.isEmpty {
                    silenceTimer?.invalidate()
                    self.stopListening()
                    Task { await self.askFollowUp(question: cleaned, result: onResult) }
                }
            }
            if error != nil {
                silenceTimer?.invalidate()
                self.stopListening()
                Task { @MainActor in self.state = .result(onResult) }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        try? audioEngine.start()
        resetSilenceTimer() // start the clock immediately on listen open
    }

    // MARK: - Helpers
    func reset() {
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        state = .capture
    }

    private func detectType(from response: String) -> ContentType {
        let lower = response.lowercased()
        if lower.contains("dollar") || lower.contains("$") || lower.contains("price") || lower.contains("cost") {
            return .price
        }
        if lower.contains("equals") || lower.contains("equation") || lower.contains("squared") || lower.contains("variable") {
            return .equation
        }
        if lower.contains("total") || lower.contains("receipt") || lower.contains("subtotal") {
            return .receipt
        }
        return .unknown
    }

    private func extractScannedText(from response: String) -> String {
        // First line often contains what was scanned — used for the hero display
        let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.first ?? response
    }
}

// MARK: - Photo capture delegate
extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }

        Task { @MainActor in
            await self.analyze(image: image)
        }
    }
}
