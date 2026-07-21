# Changelog

All notable changes to VoiceFlow are documented here.
The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## [Unreleased]

### Added
- **Rebindable hotkeys.** Both the dictation and translation keys are now
  configurable from the menu — pick any modifier (left/right ⌘ ⌥ ⌃ ⇧, Fn), or
  use *«Записать клавишу…»* to capture a modifier or an F-key (F1–F20) by
  pressing it. F-keys are handled by a `CGEventTap` that swallows the key so it
  never reaches the focused app.
- **Editable typing speed in stats.** «Сэкономлено» is now computed from your
  own words-per-minute (default 40) minus the time actually spent dictating,
  instead of a hardcoded one-second-per-word estimate.
- **«Починить микрофон» menu item** — manually trigger the mic-wedge recovery.

### Fixed
- **System-wide microphone wedge.** macOS occasionally leaves coreaudiod
  delivering bit-exact zeros to every app; VoiceFlow now detects an all-zero
  recording and revives the device by rewriting its input volume (the
  System-Settings-slider trick), automatically and on demand.
- **Hotkey silently dying.** Global event monitors are re-registered on wake,
  screen unlock, session switch and a 5-minute heartbeat; presses that arrive
  while the app is busy now flash a reason instead of being swallowed.
- **Left/right modifier confusion.** Releasing the right ⌥ while the left ⌥ was
  held no longer leaves a recording stuck — press detection uses the
  device-specific modifier bits.
- **A fresh audio engine per recording**, fixing a leaked tap after a failed
  start and a forced input device that stuck after switching back to the
  system default.
- **Crash on quit.** Every quit produced a crash report from whisper.cpp's
  static destructors (`ggml_metal_device_free` → `abort`); the app now exits
  cleanly.
