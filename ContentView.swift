import SwiftUI
import AVFoundation

// MARK: - Entry point
struct ContentView: View {
    @StateObject private var vm = CameraViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch vm.state {
            case .capture:
                CaptureView(vm: vm)
            case .processing:
                ProcessingView()
            case .result(let result):
                ResultView(vm: vm, result: result)
            case .listening:
                if case .result(let result) = vm.state {
                    ListeningView(vm: vm, result: result)
                }
            case .voiceCalc:
                VoiceCalcView(vm: vm)
            case .calcResult(let result):
                CalcResultView(vm: vm, result: result)
            case .error(let msg):
                ErrorView(message: msg) { vm.reset() }
            }
        }
        .onAppear {
            // TODO: load from Keychain in production
            vm.apiKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] ?? ""
        }
    }
}

// MARK: - Camera preview wrapper
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Screen 1: Capture
struct CaptureView: View {
    @ObservedObject var vm: CameraViewModel
    @State private var mode: String = "camera"

    var body: some View {
        VStack(spacing: 0) {
            // top bar
            HStack {
                Text("numara")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 10)

            // mode pills
            HStack(spacing: 6) {
                ForEach(["camera", "voice"], id: \.self) { m in
                    Button(action: {
                        if m == "voice" { vm.enterVoiceCalc() }
                        else { mode = m }
                    }) {
                        Text(m)
                            .font(.system(size: 12))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .background(mode == m ? Color.white.opacity(0.15) : Color.clear)
                            .foregroundColor(mode == m ? .white : .white.opacity(0.4))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(mode == m ? 0.3 : 0.1), lineWidth: 0.5))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            // viewfinder
            ZStack {
                CameraPreview(session: vm.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // corner brackets
                CornerBrackets()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    .padding(20)

                VStack {
                    Spacer()
                    Text("point at an equation, price, or receipt")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // capture button
            Button(action: { vm.capturePhoto() }) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                }
            }
            .padding(.bottom, 48)
        }
    }
}

// Corner bracket shape
struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let len: CGFloat = 24
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY + len), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + len, y: rect.minY)),
            (CGPoint(x: rect.maxX - len, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + len)),
            (CGPoint(x: rect.maxX, y: rect.maxY - len), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX - len, y: rect.maxY)),
            (CGPoint(x: rect.minX + len, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - len))
        ]
        for (a, b, c) in corners {
            p.move(to: a); p.addLine(to: b); p.addLine(to: c)
        }
        return p
    }
}

// MARK: - Processing spinner
struct ProcessingView: View {
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            Text("reading...")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Screen 2: Result
struct ResultView: View {
    @ObservedObject var vm: CameraViewModel
    let result: CameraViewModel.NumaraResult

    var body: some View {
        VStack(spacing: 0) {
            // top bar
            HStack {
                Button(action: { vm.reset() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                        Text("back")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("numara")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)

            Spacer()

            // hero — equation or price, large and centered
            switch result.type {
            case .equation:
                EquationHero(text: result.scannedText)
            case .price:
                PriceHero(text: result.scannedText)
            default:
                PriceHero(text: result.scannedText)
            }

            Spacer()

            // footer card
            FooterCard(result: result, vm: vm)
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
    }
}

struct EquationHero: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
        }
    }
}

struct PriceHero: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 48, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 24)
        }
    }
}

struct FooterCard: View {
    let result: CameraViewModel.NumaraResult
    @ObservedObject var vm: CameraViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // wave + label
            HStack(spacing: 8) {
                WaveformView()
                Text("via glasses speakers")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                // mic button — starts listening
                Button(action: {
                    vm.startListening(onResult: result)
                }) {
                    Image(systemName: "mic")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            Divider().background(Color.white.opacity(0.15))

            // plain language explanation
            Text(result.rawText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Screen 3: Listening (hey numara active)
struct ListeningView: View {
    @ObservedObject var vm: CameraViewModel
    let result: CameraViewModel.NumaraResult
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    vm.stopListening()
                    vm.state = .result(result)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14))
                        Text("back")
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 14))
                }
                Spacer()
                Text("numara")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)

            Spacer()

            // equation stays visible
            Text(result.scannedText)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // pulse ring + label
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(pulse ? 0.1 : 0.0), lineWidth: 20)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.4 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 60, height: 60)

                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.8))
            }
            .onAppear { pulse = true }

            Text("hey numara...")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 16)

            Spacer()

            // bottom footer — minimal
            VStack(alignment: .leading, spacing: 6) {
                Text("listening via ray-ban mic")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
                Text("no typing, no tapping")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Error screen
struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("something went wrong")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("try again", action: onRetry)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Voice tab entry point on capture screen
// Tapping "voice" pill enters calc mode directly
extension CaptureView {
    func enterVoiceMode() {
        vm.enterVoiceCalc()
    }
}

// MARK: - Voice calculator — always listening screen
struct VoiceCalcView: View {
    @ObservedObject var vm: CameraViewModel
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { vm.reset() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 14))
                        Text("back")
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14))
                }
                Spacer()
                Text("numara")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)

            Spacer()

            // Prompt
            Text("ask me anything")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundColor(.white)

            Text("say a number, equation, or price")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 6)

            Spacer()

            // Pulse ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(pulse ? 0.08 : 0.0), lineWidth: 24)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 60, height: 60)

                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.7))
            }
            .onAppear { pulse = true }

            Text("listening...")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.top, 14)

            Spacer()

            // Hint footer
            VStack(spacing: 4) {
                Text("say \u{201C}calculate\u{201D} or \u{201C}solve\u{201D} for exact answers")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
                Text("3 seconds of silence re-arms the mic")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.18))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Calc result screen
struct CalcResultView: View {
    @ObservedObject var vm: CameraViewModel
    let result: CameraViewModel.CalcResult
    @State private var pulse = false

    // Parse equation into up to 3 rows: top operand, operator + bottom operand, = answer
    private var equationRows: (top: String, middle: String, answer: String) {
        // Try to split on = first
        let parts = result.equation.components(separatedBy: "=")
        let answerPart = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let lhs = parts[0].trimmingCharacters(in: .whitespaces)

        // Split lhs on operator
        let ops = ["+", "\u{2212}", "-", "\u{00D7}", "\u{00F7}", "*", "/"]
        for op in ops {
            if lhs.contains(op) {
                let sides = lhs.components(separatedBy: op)
                if sides.count == 2 {
                    return (
                        top: sides[0].trimmingCharacters(in: .whitespaces),
                        middle: op + " " + sides[1].trimmingCharacters(in: .whitespaces),
                        answer: answerPart
                    )
                }
            }
        }
        // Fallback — show whole equation on one row
        return (top: lhs, middle: "", answer: answerPart)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { vm.reset() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 14))
                        Text("back")
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 14))
                }
                Spacer()
                Text("numara")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 24)

            Spacer()

            // Stacked equation — right aligned like a math paper
            VStack(alignment: .trailing, spacing: 2) {
                Text(equationRows.top)
                    .font(.system(size: 52, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                if !equationRows.middle.isEmpty {
                    Text(equationRows.middle)
                        .font(.system(size: 52, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)

                    // Divider line
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 1.5)
                        .padding(.vertical, 4)

                    Text(equationRows.answer.isEmpty ? "?" : equationRows.answer)
                        .font(.system(size: 52, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Footer — audio response + re-listening indicator
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    WaveformView()
                    Text("speaking through glasses")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)

                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(pulse ? 0.15 : 0.0), lineWidth: 8)
                            .frame(width: 20, height: 20)
                            .scaleEffect(pulse ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .frame(width: 14, height: 14)
                    }
                    .onAppear { pulse = true }

                    Text("mic re-arms automatically — ask another question")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Waveform decoration
struct WaveformView: View {
    let heights: [CGFloat] = [4, 9, 6, 11, 5, 8, 4, 10, 7]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 2, height: heights[i])
            }
        }
    }
}
