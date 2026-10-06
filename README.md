# FocusKit

A calm, focused workspace for macOS. Pick what you are working on, choose a mode, and watch it unfold while you work.

FocusKit adapts to how you use it. Students get subjects, exam countdowns and lecture notes that turn into flashcards. Professionals get projects, deadlines and meeting minutes with action items.

## Modes

- **Flight** – check in, pick a seat, scan your boarding pass, then watch your plane glide along a real great-circle route on a calm map or satellite view.
- **Orbit** – choose a mission to the Moon, Mars, Saturn or Neptune, launch, and trace one long loop around it.
- **Bloom** – plant a daisy, sunflower, tulip or lavender seed and watch it grow leaf by leaf.
- **Tide** – pick a boat and the light, cast off, and let the water rise as you read.

Every mode supports rounds with breaks in between. Breaks switch to a guided breathing scene.

## Sections

- **Focus** – intention, goal, duration, rounds and mode in one place.
- **Subjects / Projects / Goals** – weekly targets, progress rings and exam or deadline countdowns.
- **Journal** – streaks, a weekly chart by mode, a 20 week heatmap and every past session, with its notes, tasks, lecture notes or meeting minutes.

Lecture and Meeting sessions record and transcribe live on device with `SpeechAnalyzer`. When they end, Apple Intelligence turns the transcript into study notes with flashcards, or minutes with action items.
- **Side notch** – a small black notch on the right edge of the screen. Hover it to see the current session, control it, or start a new one from any app.
- **Menu bar** – remaining time and quick controls.

## Requirements

- macOS 26 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change the project layout

## Installing

The quickest way is one line in Terminal. It downloads the latest release, installs it in Applications and opens it, with no Gatekeeper prompt:

```sh
curl -fsSL https://raw.githubusercontent.com/Darkyyto/studykit/main/Scripts/install.sh | sh
```

Run the same line again to update. Your sessions, lectures and notes are kept.

Prefer the disk image? FocusKit is not notarized by Apple, so macOS asks once:

1. Download `FocusKit.dmg` from the [releases page](../../releases) and drag FocusKit into Applications.
2. Open it. macOS will say it cannot verify the developer.
3. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.

Updates are offered inside the app as well, under Settings › Updates.

## Building

```sh
git clone https://github.com/<you>/FocusKit.git
cd FocusKit
make run
```

`project.yml` is the source of truth for the Xcode project. After adding or moving files, run `make project`.

| Command | What it does |
| --- | --- |
| `make run` | Builds a debug copy and launches it |
| `make dmg` | Builds a universal release and packages `dist/FocusKit-<version>.dmg` |

Pushing a tag such as `v0.2.0` builds the disk image on GitHub Actions and attaches it to a release.


## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Switch section | ⌘1 – ⌘4 |
| Start session | ⌘↩ (hold ⌥ to skip the check-in) |
| Pause / resume | Space or ⇧⌘P |
| Skip round or break | ⇧⌘K |
| End session | ⌘. |
| New goal | ⌘N |

## Privacy

The only network traffic is map imagery for the Flight mode, loaded by Apple Maps. Goals, sessions and recordings are stored in the app container under `Application Support/FocusKit`. Speech recognition and note polishing run on this Mac; language models are downloaded by the system the first time a language is used.

## Project layout

```
FocusKit/
  App/            entry point, window, navigation and commands
  Models/         plain value types: goals, flights, recordings, airports
  Services/       persistence, flight timer, audio capture, transcription
  DesignSystem/   palette, typography and shared components
  Features/       one folder per section
```

## License

MIT. See [LICENSE](LICENSE).
