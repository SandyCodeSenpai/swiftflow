import Foundation

/// Fast transcript cleanup via Cerebras (OpenAI-compatible chat API).
/// On ANY failure or timeout the raw transcript is returned unchanged —
/// dictation must never hang or drop text because the LLM hiccuped.
struct CerebrasClient {
    let apiKey: String
    let model: String

    private static let systemPrompt = """
    You clean up voice dictation transcripts. Rules:
    - Remove filler words (um, uh, you know, like when used as filler).
    - Fix self-corrections: keep only the corrected version \
    ("send it Tuesday, no wait, Wednesday" becomes "send it Wednesday").
    - Fix obvious speech-to-text errors from context.
    - Keep the user's wording, tone, and meaning otherwise. Do not summarize.
    - Output ONLY the cleaned text. No quotes, no commentary, no preamble.
    """

    func cleanup(_ transcript: String, completion: @escaping (String) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.cerebras.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        Log.write("cerebras cleanup started (model \(model), \(transcript.count) chars)")

        // Reasoning models (gpt-oss) spend completion tokens thinking before
        // they emit text, so leave generous headroom over the transcript length.
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "max_tokens": 8192,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": transcript],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            var result = transcript
            if let error {
                Log.write("cerebras request FAILED: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Log.write("cerebras HTTP \(http.statusCode): \(detail.prefix(200))")
            } else if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String,
               case let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines),
               !cleaned.isEmpty {
                result = cleaned
                Log.write("cerebras cleanup done (\(cleaned.count) chars)")
            } else {
                Log.write("cerebras returned no usable content — using raw transcript")
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
