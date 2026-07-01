# Setup

This guide is for people who want to build and inspect the preview themselves.

## 1. Requirements

- macOS 14 or newer
- Full Xcode, with Command Line Tools installed
- XcodeGen
- Homebrew, if you want to install XcodeGen with `brew install xcodegen`
- Groq API key for online transcription
- Optional OpenAI API key for rewrite workflows and transcription fallback
- Optional for secure local transcription: a local WhisperKit/CoreML model

Install XcodeGen manually if needed:

```bash
brew install xcodegen
```

## 2. Clone And Build

```bash
git clone https://github.com/matthiasgruenwald/turbotext.git
cd turbotext
./build.sh --debug
```

To launch after building:

```bash
./build.sh --run
```

## 3. Configure API Keys

Open the app settings and paste your own Groq API key for online transcription.

Add an OpenAI API key if you want rewrite workflows or OpenAI transcription fallback.

The preview currently uses:

- Groq `whisper-large-v3-turbo` for default online transcription
- OpenAI `whisper-1` as the paid transcription fallback path
- `gpt-4o-mini` for lightweight rewriting
- `gpt-4o` for the calmer-message workflow

You are responsible for API access, billing, and data handling in your own Groq and OpenAI accounts.

Never commit your API key into this repository, issues, logs, or screenshots.

You can skip this step if you only want to test local transcription with a local WhisperKit model.

## 4. Optional Local Transcription

To use secure local transcription, choose a compatible WhisperKit CoreML model in the app and click **Installieren**. Turbotext stores models in:

```text
~/Library/Application Support/Turbotext/models/whisperkit/
```

Recommended first model: `openai_whisper-small_216MB`.

See [local-models.md](local-models.md) for the exact command, model links, and expected folder layout.

## 5. macOS Permissions

The app needs Microphone permission to record audio.

For automatic paste into the previous app, grant Accessibility permission in macOS System Settings. Without it, you can still copy and paste manually.

Turbotext does not need Full Disk Access. Auto-paste uses the Accessibility permission because the app simulates Cmd+V after putting the result on the clipboard.

## Troubleshooting

- If `xcodebuild` reports that the active developer directory is only Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- If the build cannot find XcodeGen, install it explicitly with `brew install xcodegen`.
- If online transcription fails immediately, check whether the API key is present and valid.
- If secure local mode is disabled, check whether a WhisperKit model is installed in the expected folder.
- If transcription works but paste does not, this is not an API billing issue. Check **Privacy & Security -> Accessibility**, restart Turbotext after changing the permission, and make sure the cursor is focused in a text field before starting the workflow.
- If macOS shows multiple Turbotext entries under Accessibility, remove or disable stale entries, run the app from the final location (`/Applications` if you used `./build.sh --install`), then grant the permission again.
- If the target app blocks synthetic paste or the target app was not detected, the result still stays on the clipboard so you can press Cmd+V manually.
- If audio is missing, check Microphone permission and macOS input settings.
- If you see Groq or OpenAI errors, verify model access and account billing.
