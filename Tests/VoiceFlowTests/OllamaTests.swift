import Foundation
import VoiceFlowCore

func runOllamaTests() {
    T.run("ollama: chat response parsed") {
        let json = #"{"model":"gemma3:4b","message":{"role":"assistant","content":"Привет, мир!"},"done":true}"#
        let got = try OllamaClient.parseChatResponse(json.data(using: .utf8)!)
        T.equal(got, "Привет, мир!")
    }

    T.run("ollama: error payload throws") {
        let json = #"{"error":"model 'gemma3:4b' not found"}"#
        var thrown = false
        do { _ = try OllamaClient.parseChatResponse(json.data(using: .utf8)!) }
        catch { thrown = true }
        T.expect(thrown, "error field must throw")
    }

    T.run("ollama: garbage throws") {
        var thrown = false
        do { _ = try OllamaClient.parseChatResponse(Data("not json".utf8)) }
        catch { thrown = true }
        T.expect(thrown, "non-JSON must throw")
    }
}
