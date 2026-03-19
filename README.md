# Voice Input for macOS

A privacy-first macOS menu bar dictation app. Click the menu bar icon to open the panel, record your voice, transcribe locally, and paste the text into any app — no cloud, no telemetry.

## Features

- **Menu bar app** — lightweight, always available, never in the Dock
- **Local speech recognition** — uses `coli asr` (SenseVoice / Whisper) for offline transcription
- **One-click recording** — Start / Stop dictation from the floating panel
- **Auto-paste** — transcribed text is pasted into the frontmost app via CGEvent (no AppleScript)
- **Privacy-first** — everything runs on-device

## Requirements

- macOS 14.0+ (Sonoma or later)
- [Rust](https://rustup.rs/) + Cargo
- [Swift](https://www.swift.org/) 5.9+ (Xcode 15+)
- [ffmpeg](https://ffmpeg.org/) — audio recording
- [coli CLI](https://github.com/fumiama/colima) — speech recognition

```bash
brew install ffmpeg
pip install coli-asr
```

## Running in development

```bash
# Build Rust core + stage + launch the native app in one step:
bash native/VoiceInputShell/Scripts/run-dev-app.sh
```

## Building a distributable app

```bash
# Build optimised release binaries and stage the .app bundle:
bash native/VoiceInputShell/Scripts/stage-dev-app.sh --release
```

The staged bundle lives at `native/VoiceInputShell/.stage/VoiceInputShell.app`.
Copy it to `/Applications` or package it into a `.dmg` for distribution:

```bash
hdiutil create -volname "Voice Input" \
  -srcfolder native/VoiceInputShell/.stage/VoiceInputShell.app \
  -ov -format UDZO \
  VoiceInput.dmg
```

> **Note:** The bundled app is not code-signed. For distribution outside your own machine add an
> `apple-development` or `developer-id-application` signing step after staging:
> ```bash
> codesign --deep --force --sign "Developer ID Application: Your Name" \
>   native/VoiceInputShell/.stage/VoiceInputShell.app
> ```

## Project structure

```
voice-input-mac/
├── Cargo.toml                    # Rust dylib — audio capture & ASR bridge
├── src/
│   ├── lib.rs
│   ├── audio.rs                  # ffmpeg-based recording
│   └── asr.rs                    # coli asr invocation + JSON parsing
├── include/voice_input_core.h
├── native/VoiceInputShell/       # Swift menu bar shell (active codebase)
│   ├── Sources/VoiceInputShell/
│   │   ├── App/
│   │   │   ├── VoiceInputShellApp.swift   # NSApplicationDelegate, entry point
│   │   │   ├── StatusItemController.swift # Menu bar icon & click handling
│   │   │   └── PanelController.swift      # Floating NSPanel lifecycle
│   │   ├── Bridge/
│   │   │   └── RustCoreBridge.swift       # dlopen FFI to voice-core dylib
│   │   ├── Support/
│   │   │   ├── AppPaths.swift             # Shared file paths
│   │   │   └── TextInsertionService.swift # Clipboard + CGEvent paste
│   │   └── UI/
│   │       ├── ShellViewModel.swift       # ObservableObject state machine
│   │       └── ShellPanelView.swift       # SwiftUI panel UI
│   └── Scripts/
│       ├── run-dev-app.sh        # Build Rust + Swift, stage, launch
│       └── stage-dev-app.sh     # Stage app bundle only
├── docs/
│   ├── product-spec.zh-CN.md
│   └── technical-assessment.zh-CN.md
└── .gitignore
```

## Architecture

### Rust core

Compiled as a `cdylib` and loaded at runtime by the Swift shell via `dlopen`. Exposes a C-compatible API for:
- Recording audio with ffmpeg
- Running `coli asr` and returning JSON results
- Smoke-testing the runtime environment

### Swift shell (`native/VoiceInputShell`)

Pure AppKit + SwiftUI macOS app (no Electron, no Tauri).

- `StatusItemController` — NSStatusItem with left-click toggle / right-click quit menu
- `PanelController` — creates a borderless, floating `NSPanel`; wires ViewModel callbacks
- `RustCoreBridge` — `dlopen`s the Rust dylib, resolves C symbols, decodes JSON
- `ShellViewModel` — `ObservableObject` driving recording state, transcription, status footer
- `ShellPanelView` — SwiftUI layout: pinned header → scrollable content → compact status footer
- `TextInsertionService` — writes to pasteboard, simulates ⌘V via `CGEvent`

## Internal Docs

- [Product Spec](docs/product-spec.zh-CN.md)
- [Technical Assessment](docs/technical-assessment.zh-CN.md)

## License

MIT — see [LICENSE](LICENSE) for details.
