# VoiceFlow

**Local, free voice dictation for macOS with AI cleanup — a self-hosted alternative to [Wispr Flow](https://wisprflow.ai).**

Hold a key, speak, release — polished text appears in whatever app you're typing in. Everything runs on your Mac: no cloud, no subscription, no audio ever leaves the machine.

```
[Right ⌥] → [Record] → [Whisper: speech→text] → [Local LLM: cleanup] → [Text at your cursor]
```

## Features

- 🎙 **Push-to-talk dictation** — hold right ⌥ Option, speak, release. Or quick-tap for hands-free mode: recording runs until the next tap.
- 🧹 **AI cleanup** — a local LLM removes filler words («э-э», "um"), collapses self-corrections (*"on Friday… no, Saturday"* → *"on Saturday"*), and fixes punctuation. If the LLM is down, the raw transcript is inserted — dictation always works.
- 🌍 **Translate mode** — hold right ⌘ instead: dictate in Russian, English comes out.
- 📺 **Live transcription** — a floating capsule shows a live waveform and the text as you speak; or stream it straight into the focused text field.
- 📖 **Personal dictionary** — teach Whisper your names, brands, and jargon (plain text file).
- 📊 **Stats window** — words per day chart, total dictations, estimated time saved.
- 🎧 **Mic picker, sounds, auto-gain** — choose an input device, get audio feedback, and quiet microphones are normalized automatically.
- 🇷🇺🇬🇧 **Russian + English** — including code-switching mid-sentence.

Recognition: OpenAI **Whisper** (`large-v3-turbo`, quantized) via [whisper.cpp](https://github.com/ggml-org/whisper.cpp) with Metal — ~1 second per phrase on Apple Silicon. Cleanup/translation: **qwen3:4b-instruct** via [Ollama](https://ollama.com).

## Requirements

- macOS 14+ on Apple Silicon (16 GB RAM recommended)
- [Homebrew](https://brew.sh) for the AI cleanup step
- ~4.5 GB disk: Whisper model (~550 MB, auto-downloaded on first launch) + LLM (~2.5 GB, optional)

## Install from release

1. Download `VoiceFlow.zip` from [Releases](../../releases), unzip, drag **VoiceFlow.app** to `/Applications`.
2. The app is not notarized (it's a hobby project — no Apple Developer subscription), so on first launch: **right-click → Open → Open**. If macOS still refuses:
   ```bash
   xattr -dr com.apple.quarantine /Applications/VoiceFlow.app
   ```
3. Launch it. Grant the two permissions it asks for: **Microphone** and **Accessibility** (needed for the global hotkey and text insertion).
4. The Whisper model downloads automatically on first run (progress shows in the menu bar).
5. *(Optional but recommended)* Enable AI cleanup:
   ```bash
   brew install ollama
   brew services start ollama
   ollama pull qwen3:4b-instruct
   ```
6. Hold **right ⌥** and talk. That's it.

## Build from source

No Xcode needed — Command Line Tools are enough (`xcode-select --install`).

```bash
git clone https://github.com/ex2mple/VoiceFlow.git && cd VoiceFlow
brew install cmake
make whisper   # once: builds whisper.cpp as static libs (Metal)
make model     # once: downloads the Whisper model (~550 MB)
make ai        # once: installs/starts Ollama, pulls qwen3:4b-instruct
make cert      # once: local signing cert so permissions survive rebuilds
make install   # build → sign → /Applications
make test      # unit tests (custom runner; XCTest needs Xcode)
```

End-to-end test — synthesizes Russian speech with `say`, runs it through the real Whisper + Ollama:

```bash
say -v Milena -o /tmp/d.aiff "Ну, короче, запиши меня на субботу" && \
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/d.aiff /tmp/d.wav
VOICEFLOW_E2E=1 VOICEFLOW_E2E_WAV=/tmp/d.wav make test
```

## How it works

| Stage | Tech | Notes |
|---|---|---|
| Hotkey | `NSEvent` global monitor | right ⌥ dictate / right ⌘ translate; tap = hands-free |
| Audio | `AVAudioEngine` → 16 kHz mono | silence gate + peak auto-gain |
| Speech→text | whisper.cpp, `large-v3-turbo` q5_0 | Metal, flash attention, user dictionary via `initial_prompt` |
| Cleanup | Ollama `qwen3:4b-instruct` | few-shot prompt; length validator rejects "summarizing"; falls back to raw text |
| Insertion | clipboard + synthetic ⌘V | previous clipboard restored; or live typing via synthetic key events |

Project layout: `Sources/VoiceFlowCore` — AppKit-free logic, fully unit-tested (Whisper hallucination filter, silence gate, LLM output validators, Ollama client, stats). `Sources/VoiceFlow` — the menu bar app. `Sources/CWhisper` — whisper.cpp headers for Swift; static libs built by `scripts/build-whisper.sh`.

## Troubleshooting

- **Hotkey stopped responding** (e.g. after sleep) — the app re-registers its listeners on wake and has a watchdog, but if it ever happens: quit and relaunch from the menu bar icon.
- **"Вставлено без ИИ-чистки"** — Ollama isn't running (`brew services start ollama`) or the model isn't pulled.
- **Nothing inserts** — check Accessibility permission; the text is always in the clipboard and in the History menu as a fallback.
- **Whisper hallucinates on silence** («Субтитры сделал DimaTorzok») — known Whisper quirk; the built-in filter catches the common ones, PRs with new phrases welcome.

## License

MIT — see [LICENSE](LICENSE).
