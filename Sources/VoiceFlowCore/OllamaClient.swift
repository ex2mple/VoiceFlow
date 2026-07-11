import Foundation

public struct OllamaError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// Minimal client for a local Ollama daemon.
public final class OllamaClient {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
                timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    public func isAvailable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    public func hasModel(_ name: String) async -> Bool {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        guard let (data, _) = try? await session.data(for: request) else { return false }
        return Self.parseTags(data).contains { $0 == name || $0 == name + ":latest" }
    }

    /// {"models":[{"name":"qwen3:4b-instruct"},…]} → names
    public static func parseTags(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    public struct PullProgress {
        public let status: String
        public let percent: Int?
    }

    /// Streaming JSONL line from /api/pull → progress.
    public static func parsePullLine(_ line: String) throws -> PullProgress {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        else { throw OllamaError("Non-JSON pull line") }
        if let err = json["error"] as? String { throw OllamaError(err) }
        let status = json["status"] as? String ?? ""
        var percent: Int?
        if let total = json["total"] as? Int64, total > 0,
           let completed = json["completed"] as? Int64 {
            percent = Int(completed * 100 / total)
        }
        return PullProgress(status: status, percent: percent)
    }

    /// Downloads a model into the local Ollama (like `ollama pull`).
    public func pull(model: String, onProgress: @escaping (PullProgress) -> Void) async throws {
        // The shared session has short timeouts; a multi-GB pull needs its own.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 4 * 3600
        let pullSession = URLSession(configuration: config)
        defer { pullSession.finishTasksAndInvalidate() }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "stream": true,
        ])

        let (bytes, response) = try await pullSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        for try await line in bytes.lines where !line.isEmpty {
            onProgress(try Self.parsePullLine(line))
        }
    }

    public func chat(model: String, system: String, user: String) async throws -> String {
        try await chat(model: model, messages: [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ])
    }

    public func chat(model: String, messages: [[String: String]]) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            // Keep the model resident so dictation never pays the ~6s cold load.
            "keep_alive": "30m",
            "messages": messages,
            "options": ["temperature": 0],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(text)")
        }
        return try Self.parseChatResponse(data)
    }

    /// Extracted for testability: {"message": {"content": "..."}}
    public static func parseChatResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError("Non-JSON response")
        }
        if let err = json["error"] as? String { throw OllamaError(err) }
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OllamaError("Unexpected response shape")
        }
        return content
    }
}
