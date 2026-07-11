import CWhisper
import Foundation

public struct WhisperError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// Thin wrapper over whisper.cpp. Not thread-safe: callers must serialize
/// transcribe() calls (DictationCoordinator uses one serial queue).
public final class WhisperEngine {
    private let ctx: OpaquePointer

    public init(modelPath: String) throws {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw WhisperError("Не удалось загрузить модель: \(modelPath)")
        }
        self.ctx = ctx
    }

    deinit {
        whisper_free(ctx)
    }

    /// samples: mono float32 PCM at 16 kHz.
    public func transcribe(_ samples: [Float]) -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(8, ProcessInfo.processInfo.activeProcessorCount))
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.translate = false
        params.suppress_blank = true

        let status = "auto".withCString { lang -> Int32 in
            params.language = lang
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
        }
        guard status == 0 else { return "" }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cstr)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
