# Voice Input for macOS

A local voice input tool for macOS that works like a lightweight speech input method. Press a global hotkey to start recording, transcribe your voice locally, and insert the text into the current application.

![Screenshot](https://github.com/YOUR_USERNAME/voice-input-mac/raw/main/screenshot.png)

## Features

- **Global Hotkey**: Use `Cmd+Shift+V` to toggle recording from anywhere
- **Local Speech Recognition**: Uses `coli asr` for offline transcription (SenseVoice/Whisper models)
- **Auto-Paste**: Automatically pastes transcribed text to your current application
- **Transcription History**: Keep track of recent transcriptions
- **Privacy-First**: All processing happens locally on your machine

## Requirements

- macOS 13.0+ (Ventura or later)
- [Rust](https://rustup.rs/) and Cargo
- [Node.js](https://nodejs.org/) (for development)
- [ffmpeg](https://ffmpeg.org/) for audio recording
- [coli CLI](https://github.com/fumiama/colima) for speech recognition

### Installing Dependencies

```bash
# Install ffmpeg
brew install ffmpeg

# Install coli CLI
pip install coli-asr
```

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/voice-input-mac.git
cd voice-input-mac

# Install Rust dependencies and build
cd src-tauri
cargo build

# Or use Tauri CLI
cargo tauri build
```

## Usage

1. **Start Recording**: Click "Start Recording" or press `Cmd+Shift+V`
2. **Speak**: Record your voice (up to 5 minutes)
3. **Stop**: Click "Stop Recording" or press `Cmd+Shift+V` again
4. **Paste**: The transcribed text is automatically pasted into your active application

## Settings

- **Global Hotkey**: Customize the hotkey combination (default: `Cmd+Shift+V`)
- **ASR Model**: Choose between SenseVoice (faster) or Whisper (more accurate)
- **AI Polish**: Remove filler words and fix punctuation
- **Auto-Paste**: Automatically paste after transcription
- **Paste Method**: Choose between AppleScript or clipboard paste

## Development

```bash
# Start the frontend dev server and Tauri app
npm run tauri:dev

# Build frontend assets for desktop packaging
npm run build
```

## Project Structure

```
voice-input-mac/
├── src-tauri/          # Rust backend
│   ├── src/
│   │   ├── audio.rs    # Audio recording (ffmpeg)
│   │   ├── asr.rs      # Speech recognition (coli)
│   │   ├── clipboard.rs# Clipboard operations
│   │   ├── hotkey.rs   # Global hotkey handling
│   │   ├── settings.rs # Settings and history storage
│   │   └── lib.rs      # Main app entry point
│   └── tauri.conf.json # Tauri configuration
├── src/                # Editable frontend source
│   ├── index.html
│   ├── styles.css
│   └── app.js
├── scripts/            # Frontend build and dev helpers
│   ├── build-frontend.mjs
│   └── dev-frontend.mjs
├── package.json        # Frontend and Tauri helper scripts
├── dist/               # Frontend assets
│   ├── index.html
│   ├── styles.css
│   └── app.js
└── README.md
```

## Architecture

### Backend (Rust + Tauri 2)

- **Audio Recording**: Uses ffmpeg to record audio from the default microphone
- **Speech Recognition**: Calls `coli asr` CLI for local transcription
- **Clipboard**: Uses pbcopy/pbpaste and osascript for cross-app pasting
- **Hotkey**: Uses Tauri's global-shortcut plugin for global speech input triggering
- **Storage**: JSON file in `~/.voice-input-mac/settings.json`

### Frontend (Vanilla JavaScript)

- No framework dependencies
- Lightweight and fast
- Compatible with Tauri 2's invoke/listen APIs

## Internal Docs

- [Reverse Product Spec (ZH-CN)](docs/product-spec.zh-CN.md)
- [Technical Assessment and Refactor Plan (ZH-CN)](docs/technical-assessment.zh-CN.md)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- [Tauri](https://tauri.app/) - Cross-platform desktop framework
- [coli](https://github.com/fumiama/colima) - Local speech recognition
- [ffmpeg](https://ffmpeg.org/) - Audio recording
