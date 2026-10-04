# Voicer

Menu bar dictation for macOS. Hold a hotkey, speak Russian, English, or a mix of both, and release. Voicer transcribes on your Mac with Whisper, has Claude translate and tidy the text into English, and types the result into the focused text field. If no text field has focus, the result goes to the clipboard.

## How it works

1. A global hotkey starts recording. Hold to talk, release to finish. A quick tap starts hands-free mode. Tap again to finish, or press Esc to cancel.
2. [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) transcribes the audio locally on the Neural Engine. The first launch downloads the model (about 630 MB) to `~/Library/Application Support/Voicer/models` and compiles it for your chip, which takes a few minutes. After that it loads in seconds.
3. An AI model (Claude by default, or Codex) translates to English, removes filler and false starts, applies self-corrections, and adds light formatting. The formatting depends on the target app: paragraphs and numbered lists in docs and mail, compact text in chat apps, plain text in terminals and IDEs.
4. Voicer checks the focused element with the Accessibility API. If it's editable, Voicer pastes with ⌘V and then restores your clipboard. Otherwise the text stays on the clipboard.

Each output mode can have its own shortcut:

- **Translate to English**, on ⌃⌥ by default
- **Clean up, keep language**
- **Raw transcript**, no Claude call

Voicer calls the AI through a command line tool you already use, so it runs on your existing subscription with no API key:

- **Claude**: [Claude Code](https://claude.com/claude-code) (`claude -p`), with tools, MCP servers, and settings files turned off.
- **Codex**: the [Codex CLI](https://github.com/openai/codex) (`codex exec`), read-only and ephemeral, ignoring your Codex config.

If the CLI is missing or the call fails, Voicer inserts the raw transcript and says why in the overlay.

## Build and install

Requires macOS 15+, Apple Silicon, Xcode 16+, and either Claude Code or the Codex CLI, logged in.

```sh
# One time: create a local signing identity so macOS keeps permissions across rebuilds
scripts/create-signing-cert.sh

SIGN_IDENTITY="Voicer Local Signing" scripts/build-app.sh --install
```

Without `SIGN_IDENTITY`, the app is ad-hoc signed. That works, but macOS treats every rebuild as a new app, so you have to remove and re-add it under Accessibility each time.

## First run

1. Allow microphone access when prompted.
2. Grant Accessibility in System Settings > Privacy & Security > Accessibility. Voicer needs it to see the hotkey in other apps, check the focused field, and paste.
3. Under Settings > AI, pick Claude or Codex, then pick the account. Voicer finds every login on your Mac, including extra ones you keep in `~/.claude-*` (`CLAUDE_CONFIG_DIR`) or `~/.codex-*` (`CODEX_HOME`) folders. Press Test connection.

## Settings

| Setting | Default | Notes |
|---|---|---|
| Shortcuts | ⌃⌥ for Translate | Record any modifier chord (⌃⌥, Right ⌥, fn) or modifier + key (⌥Space) per mode. If you use fn, set System Settings > Keyboard > "Press 🌐 key to" to "Do Nothing". |
| Behavior | Hold, or tap for hands-free | Also hold-only and press-to-toggle. |
| I speak | Russian | Forcing Russian handles mixed speech better than auto-detect, which sometimes picks English and drops the Russian parts. |
| Whisper model | Large v3 Turbo | Large v3 is a bit more accurate and slower. |
| AI provider | Claude | Claude answers in about 2.5 s, Codex in about 6 s. |
| Model, effort | `claude-sonnet-5-5` medium; Codex default model, medium | |
| Glossary | empty | Names and terms to spell exactly. Whisper gets them as a prompt, which makes it write `Kubernetes` instead of `куберниц`. Claude gets them too. |

## Code map

| File | Role |
|---|---|
| `Shortcut.swift` | Shortcut model, matching, keycap labels |
| `HotkeyMonitor.swift` | `CGEventTap` capture and the hold, tap, and toggle state machine |
| `ShortcutRecorder.swift` | Click-to-record shortcut field |
| `AudioRecorder.swift` | `AVAudioEngine` capture, resampled to 16 kHz mono |
| `Transcriber.swift` | WhisperKit download, load, transcribe, and the silence hallucination filter |
| `TextFormatter.swift` | Claude prompt and per-app formatting styles |
| `AIProvider.swift` | Provider and account model |
| `CLIRunner.swift` | Runs a CLI process with a clean environment |
| `ClaudeClient.swift` | Claude Code accounts and `claude -p` call |
| `CodexClient.swift` | Codex accounts and `codex exec` call |
| `TextInserter.swift` | Focused-field check and paste with clipboard restore |
| `AppModel.swift` | Pipeline and state |
| `Overlay.swift` | Floating recording and status pill |
| `MenuBarView.swift` | Menu bar panel |
| `SettingsView.swift` | Settings window tabs |
| `VoicerApp.swift` | App entry point |

## Troubleshooting

Settings > Shortcuts shows the modifier keys Voicer sees right now. If that stays empty while you hold keys, re-enable Voicer under Accessibility and relaunch it. Startup diagnostics go to `~/Library/Logs/Voicer.log`.

## License

MIT, see [LICENSE](LICENSE).
