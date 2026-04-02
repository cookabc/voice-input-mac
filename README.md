# Murmur

A privacy-first macOS menu bar dictation app. Click the icon, speak, and your words are pasted directly into whatever you're typing in — no cloud, no telemetry, no subscription.

## Features

- **Menu bar app** — lightweight, always available, never in the Dock
- **Live preview** — parallel on-device speech recognition (zh-CN, zh-TW, en-US) while recording
- **Offline transcription** — final pass via `coli asr` (SenseVoice) bundled inside the app
- **Auto-paste** — transcribed text is pasted into the frontmost app via CGEvent (no AppleScript)
- **LLM Polish** — optional grammar/punctuation cleanup via any OpenAI-compatible API
- **Privacy-first** — microphone audio never leaves your machine

## Requirements

- macOS 26.0+
- Swift 6.3+ (Xcode 17+) — for building from source
- [`@marswave/coli`](https://www.npmjs.com/package/@marswave/coli) — SenseVoice transcription CLI, bundled at build time

```bash
npm install -g @marswave/coli
```

## Running in development

```bash
./dev.sh
```

Builds the Swift package, stages `Murmur.app` under `.stage/`, kills any running instance, and opens the new build.

Do not launch `.build/.../Murmur` directly. macOS privacy prompts for microphone and speech recognition require the staged `.app` bundle and its `Info.plist` usage descriptions.

Other modes:

```bash
./dev.sh --no-run      # build + stage only
./dev.sh --release     # release build + stage + launch
./dev.sh --release --no-run
```

## Building a distributable bundle

```bash
./dev.sh --release --no-run
```

The staged bundle is at `.stage/Murmur.app`.

```bash
# Package as DMG
hdiutil create -volname "Murmur" \
  -srcfolder .stage/Murmur.app \
  -ov -format UDZO \
  Murmur.dmg
```

> **Note:** The bundle is unsigned. For distribution outside your own machine, sign it:
>
> ```bash
> codesign --deep --force --sign "Developer ID Application: Your Name" \
>   .stage/Murmur.app
> ```

## Project structure

```
murmur/
├── Package.swift
├── dev.sh                Build + stage + launch (--no-run, --release flags)
├── Sources/
│   ├── App/              Entry point, NSStatusItem, NSPanel
│   ├── Engine/           Audio recording, live ASR, coli, LLM polish
│   ├── Support/          Path resolution, CGEvent paste
│   └── UI/               SwiftUI panel + view model
└── docs/
    ├── product-spec.zh-CN.md
    └── technical-assessment.zh-CN.md
```

## Architecture

```
AVAudioEngine ──buffers──▶ LiveSpeechRecognizer  (parallel zh-CN / zh-TW / en-US)
     │                              │
     │                       liveTranscript (real-time SwiftUI preview)
     │
     └── WAV file ──────────▶ ColiTranscriber  (coli asr subprocess)
                                    │
                              transcriptText (SwiftUI)
                                    │
                            LLMPolisher  (optional, OpenAI-compatible API)
                                    │
                             polishedText (SwiftUI)
                                    │
                      TextInsertionService → CGEvent ⌘V → frontmost app
```

## Internal Docs

- [Product Spec](docs/product-spec.zh-CN.md)
- [Technical Assessment](docs/technical-assessment.zh-CN.md)

## License

MIT
