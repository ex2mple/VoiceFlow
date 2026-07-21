# VoiceFlow

**Local, free voice dictation for macOS with AI cleanup — a self-hosted alternative to [Wispr Flow](https://wisprflow.ai).**

Hold a key, speak, release — polished text appears in whatever app you're typing in. Everything runs on your Mac: no cloud, no subscription, no audio ever leaves the machine.

```
[Right ⌥] → [Record] → [Whisper: speech→text] → [Local LLM: cleanup] → [Text at your cursor]
```

## Features

- 🎙 **Push-to-talk dictation** — hold right ⌥ Option (or record your own key: any modifier or F-key), speak, release. Or quick-tap for hands-free mode: recording runs until the next tap.
- 🧹 **AI cleanup** — a local LLM removes filler words («э-э», "um"), collapses self-corrections (*"on Friday… no, Saturday"* → *"on Saturday"*), and fixes punctuation. If the LLM is down, the raw transcript is inserted — dictation always works.
- 🌍 **Translate mode** — hold right ⌘ (also configurable) instead: dictate in Russian, English comes out.
- 📺 **Live transcription** — a floating capsule shows a live waveform and the text as you speak; or stream it straight into the focused text field.
- 📖 **Personal dictionary** — teach Whisper your names, brands, and jargon (plain text file).
- ⌨️ **Rebindable hotkeys** — pick any modifier for dictation and translation from the menu, or *«Записать клавишу…»* to capture a modifier or F-key by pressing it.
- 📊 **Stats window** — words per day chart, total dictations, and time saved computed against *your own* typing speed (editable, words/min).
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
5. *(Optional but recommended)* Enable AI cleanup & translation: install [Ollama](https://ollama.com/download/mac) and launch it — that's the only extra step. VoiceFlow detects it and **downloads the LLM (~2.5 GB) by itself**, with progress in the menu bar. (Terminal folks can `brew install ollama && brew services start ollama` instead. If you skip this entirely, dictation still works — you just get Whisper's raw transcript.)
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
| Hotkey | `NSEvent` monitors + CGEventTap | recordable: any modifier or F1–F20 (F-keys are swallowed by the tap so they don't reach apps); tap = hands-free |
| Audio | `AVAudioEngine` → 16 kHz mono | silence gate + peak auto-gain |
| Speech→text | whisper.cpp, `large-v3-turbo` q5_0 | Metal, flash attention, user dictionary via `initial_prompt` |
| Cleanup | Ollama `qwen3:4b-instruct` | few-shot prompt; length validator rejects "summarizing"; falls back to raw text |
| Insertion | clipboard + synthetic ⌘V | previous clipboard restored; or live typing via synthetic key events |

Project layout: `Sources/VoiceFlowCore` — AppKit-free logic, fully unit-tested (Whisper hallucination filter, silence gate, LLM output validators, Ollama client, stats). `Sources/VoiceFlow` — the menu bar app. `Sources/CWhisper` — whisper.cpp headers for Swift; static libs built by `scripts/build-whisper.sh`.

## Troubleshooting

- **Hotkey stopped responding** — the app re-registers its listeners on wake, screen unlock, session switch and on a 5-minute heartbeat, and flashes a reason in the menu bar when a press is ignored (model loading, previous recording still processing). If it still happens: check Secure Input (a password field or Terminal's Secure Keyboard Entry blocks global event monitors system-wide), or quit and relaunch from the menu bar icon.
- **Microphone records silence in every app** (a macOS-wide coreaudiod wedge) — VoiceFlow detects an all-zero recording, revives the device automatically and asks you to retry; «Починить микрофон» in the menu does the same on demand.
- **F-key hotkey does nothing** — on Mac keyboards the top row sends media keys by default; hold **Fn** with it, or enable *«Use F1, F2, etc. as standard function keys»* in System Settings → Keyboard. Assigning an F-key also needs Accessibility permission (for the event tap).
- **"Вставлено без ИИ-чистки"** — Ollama isn't running (`brew services start ollama`) or the model isn't pulled.
- **Nothing inserts** — check Accessibility permission; the text is always in the clipboard and in the History menu as a fallback.
- **Whisper hallucinates on silence** («Субтитры сделал DimaTorzok») — known Whisper quirk; the built-in filter catches the common ones, PRs with new phrases welcome.

## License

MIT — see [LICENSE](LICENSE).
