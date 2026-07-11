import Foundation

public enum ModelLocator {
    public static let modelFileName = "ggml-large-v3-turbo-q5_0.bin"
    public static let modelDownloadURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!

    public static func supportDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VoiceFlow/models", isDirectory: true)
    }

    public static func modelPath() -> URL {
        supportDirectory().appendingPathComponent(modelFileName)
    }

    public static var modelExists: Bool {
        FileManager.default.fileExists(atPath: modelPath().path)
    }
}
