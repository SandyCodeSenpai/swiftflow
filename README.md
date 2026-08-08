# SwiftFlow

Wispr Flow–style push-to-talk dictation for macOS. Hold **Right Option (⌥)**,
speak, release — the transcript is cleaned up and pasted into whatever app
has focus.

Pipeline: mic (16 kHz PCM) → Deepgram nova-3 streaming WebSocket →
Cerebras LLM cleanup (optional, toggle in the menu) → clipboard + synthetic
Cmd+V injection.

## Setup

1. Put your API keys in `~/.swiftflow/config.json`:

   ```json
   {
     "deepgram_api_key": "...",
     "cerebras_api_key": "...",
     "cerebras_model": "llama-3.3-70b",
     "cleanup_enabled": true
   }
   ```

2. Build and run:

   ```sh
   ./build_app.sh
   open SwiftFlow.app
   ```

3. Grant permissions on first launch (both required):
   - **Microphone** — prompted automatically.
   - **Accessibility** — System Settings → Privacy & Security → Accessibility
     → enable SwiftFlow. Needed for both the hotkey listener and the Cmd+V
     injection. After granting, quit and relaunch the app.

## Usage

- A 🎙 icon appears in the menu bar. Hold Right ⌥ and talk (icon turns 🔴),
  release (⏳), and the text lands at your cursor.
- Menu → "AI Cleanup (Cerebras)" toggles the LLM pass. Off = raw Deepgram
  transcript (still punctuated/capitalized via smart_format), lowest latency.

## Troubleshooting

- **Nothing pastes**: Accessibility permission missing, or you edited the
  binary after granting it (re-toggle the checkbox in System Settings).
- **Empty transcripts**: check the Deepgram key, or the mic permission was
  denied.
- **Auto-start at login**: System Settings → General → Login Items → add
  SwiftFlow.app.
