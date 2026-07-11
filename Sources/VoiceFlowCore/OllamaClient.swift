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
                timeout: TimeInterval = 8) {
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

    public func chat(model: String, system: String, user: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "options": ["temperature": 0.1],
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
