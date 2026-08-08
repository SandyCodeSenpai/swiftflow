import Foundation

/// One live-transcription session over Deepgram's streaming WebSocket.
/// Create a fresh instance per dictation. Audio sent before the socket
/// opens is buffered and flushed on connect, so no speech is lost even
/// if the user starts talking instantly.
final class DeepgramClient: NSObject, URLSessionWebSocketDelegate {
    var onFinalTranscript: ((String) -> Void)?

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connected = false
    private var finishRequested = false
    private var completed = false
    private var pendingAudio: [Data] = []
    private var finals: [String] = []

    init(apiKey: String) {
        super.init()
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: request)
    }

    func connect() {
        task?.resume()
        receiveLoop()
    }

    func send(_ data: Data) {
        DispatchQueue.main.async {
            if self.connected {
                self.task?.send(.data(data)) { _ in }
            } else {
                self.pendingAudio.append(data)
            }
        }
    }

    /// Stop sending audio and ask Deepgram to flush remaining results.
    func finish() {
        DispatchQueue.main.async {
            self.finishRequested = true
            if self.connected { self.sendCloseStream() }
            // Safety net: never leave the user hanging if the network stalls.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.complete() }
        }
    }

    private func sendCloseStream() {
        task?.send(.string(#"{"type":"CloseStream"}"#)) { _ in }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text) }
                self.receiveLoop()
            case .failure:
                DispatchQueue.main.async { self.complete() }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let type = json["type"] as? String
        if type == "Results",
           json["is_final"] as? Bool == true,
           let channel = json["channel"] as? [String: Any],
           let alternatives = channel["alternatives"] as? [[String: Any]],
           let transcript = alternatives.first?["transcript"] as? String,
           !transcript.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.async { self.finals.append(transcript) }
        } else if type == "Metadata" {
            // Deepgram sends Metadata after CloseStream — transcription is done.
            DispatchQueue.main.async { self.complete() }
        }
    }

    private func complete() {
        guard finishRequested, !completed else { return }
        completed = true
        task?.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        onFinalTranscript?(finals.joined(separator: " "))
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.connected = true
            for chunk in self.pendingAudio { self.task?.send(.data(chunk)) { _ in } }
            self.pendingAudio.removeAll()
            if self.finishRequested { self.sendCloseStream() }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { self.complete() }
    }
}
