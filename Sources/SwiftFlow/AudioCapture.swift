import AVFoundation

/// Captures the default microphone and hands back 16 kHz mono Int16 PCM
/// chunks — the exact format the Deepgram socket is opened with.
final class AudioCapture {
    var onAudio: ((Data) -> Void)?
    /// Normalized 0…1 mic level, delivered on the main thread. Drives the HUD waveform.
    var onLevel: ((CGFloat) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    /// Preallocates audio I/O resources so the next start() is near-instant
    /// instead of paying the hardware spin-up cost mid-dictation.
    func warmUp() {
        // prepare() throws an NSException unless the engine has an I/O node;
        // touching inputNode instantiates it.
        _ = engine.inputNode
        engine.prepare()
    }

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "SwiftFlow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Microphone unavailable (permission not granted?)"
            ])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            if let level = Self.level(of: buffer) {
                DispatchQueue.main.async { self.onLevel?(level) }
            }
            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0, let channel = out.int16ChannelData else { return }
            let data = Data(bytes: channel[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
            self.onAudio?(data)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        engine.prepare()
    }

    /// RMS of the buffer mapped to 0…1 on a rough dB scale (-50 dB…0 dB).
    private static func level(of buffer: AVAudioPCMBuffer) -> CGFloat? {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += samples[i] * samples[i] }
        let rms = sqrt(sum / Float(n))
        guard rms.isFinite, rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return CGFloat(min(1, max(0, (db + 50) / 50)))
    }
}
