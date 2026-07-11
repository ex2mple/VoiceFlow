import Foundation
import VoiceFlowCore

func runOllamaPullTests() {
    T.run("pull: progress line parsed") {
        let p = try OllamaClient.parsePullLine(
            #"{"status":"pulling abc","total":1000,"completed":250}"#)
        T.equal(p.percent, 25)
        T.equal(p.status, "pulling abc")
    }

    T.run("pull: status-only line has no percent") {
        let p = try OllamaClient.parsePullLine(#"{"status":"verifying sha256 digest"}"#)
        T.equal(p.percent, nil)
    }

    T.run("pull: error line throws") {
        var thrown = false
        do { _ = try OllamaClient.parsePullLine(#"{"error":"pull model manifest: file does not exist"}"#) }
        catch { thrown = true }
        T.expect(thrown, "error line must throw")
    }

    T.run("tags: model names parsed") {
        let data = Data(#"{"models":[{"name":"qwen3:4b-instruct","size":1},{"name":"gemma3:4b"}]}"#.utf8)
        T.equal(OllamaClient.parseTags(data), ["qwen3:4b-instruct", "gemma3:4b"])
        T.equal(OllamaClient.parseTags(Data("{}".utf8)), [])
    }
}
