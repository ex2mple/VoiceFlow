import Foundation
import VoiceFlowCore

/// Downloads the Whisper model on first launch (~550 MB).
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var onProgress: ((Int) -> Void)?
    private var onDone: ((Result<Void, Error>) -> Void)?
    private var session: URLSession?

    func download(onProgress: @escaping (Int) -> Void,
                  onDone: @escaping (Result<Void, Error>) -> Void) {
        self.onProgress = onProgress
        self.onDone = onDone
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: ModelLocator.modelDownloadURL).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Int(totalBytesWritten * 100 / totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            let dest = ModelLocator.modelPath()
            try FileManager.default.createDirectory(
                at: ModelLocator.supportDirectory(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            onDone?(.success(()))
        } catch {
            onDone?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error { onDone?(.failure(error)) }
        self.session?.finishTasksAndInvalidate()
    }
}
