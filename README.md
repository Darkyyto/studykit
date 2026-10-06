<p align="center">
  <img src="docs/banner.png" alt="FocusKit" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Darkyyto/studykit/releases/latest/download/FocusKit.dmg"><b>Download for Mac</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/Darkyyto/studykit/releases">Releases</a>
  &nbsp;·&nbsp;
  macOS 26 or later
</p>

# FocusKit

A calm workspace for your Mac. Say what you are working on, pick a mode, and watch the session unfold while you focus. Lectures and meetings are recorded, transcribed and turned into notes, all on device.

FocusKit adapts to who you are. Students get subjects, exam countdowns and lectures that turn into flashcards. Professionals get projects, deadlines and meeting minutes with action items. You can switch profile at any time.

## Installing

One line in Terminal downloads the latest version, installs it in Applications and opens it:

```sh
curl -fsSL https://raw.githubusercontent.com/Darkyyto/studykit/main/Scripts/install.sh | sh
```

Prefer the disk image? Download `FocusKit.dmg` from the [releases page](../../releases) and drag FocusKit into Applications. FocusKit is not notarized by Apple, so the first time macOS asks you to confirm it in **System Settings › Privacy & Security › Open Anyway**.

After that, updates install themselves. When a new version is out, FocusKit shows it at the bottom of the window: press **Update**, then **Restart and Update**. Your session is saved, the app is replaced and it opens again where you left it. A backup of your library is made before every update.

## Modes

- **Flight** – your session becomes a flight along a real route, followed on a calm map or satellite view, with clouds passing under the plane.
- **Orbit** – a satellite traces one long loop around a planet, with its moon, a nebula and the odd shooting star.
- **Bloom** – a seed grows leaf by leaf on a quiet hill and flowers when you finish.
- **Tide** – the water rises around a small boat as the session goes on.

Sessions can have several rounds with breaks in between. Breaks switch to a guided breathing scene, or to a few flashcards when you are studying.

## Sections

- **Focus** – what you are working on, the mode, the duration and, under Customize, the session type, rounds, subject, a PDF to read and a task list.
- **Subjects** (or Projects, or Goals) – weekly targets and exam or deadline countdowns. Open a subject to see everything in it: its lectures, PDFs, flashcards and recent sessions, and add more.
- **Lectures** (or Meetings) – every recording, grouped by day, with search and subject filters. Rename, move, merge, export as PDF or delete, one at a time or several at once with **Select**.
- **Journal** – streaks, a weekly chart, a 20 week heatmap and every past session with its notes.

## Recording

Lecture and Meeting sessions record while you focus. The live transcript appears beside your own notes.

- Quiet or distant voices are boosted and low hum is filtered out, so a professor across the room is still heard.
- The transcript is saved every few seconds and the audio survives a crash. An interrupted recording is recovered the next time FocusKit opens.
- When the recording ends, the whole lecture is transcribed again with a more accurate model. Apple Intelligence then fixes misheard words from context and writes clean notes, a summary and flashcards, or minutes with decisions and action items.
- Recording keeps going while you use other sections and stops when the session ends. It can also be stopped from Lectures, the notch or the menu bar.
- Two parts of the same lecture can be merged into one, audio, transcript, notes and flashcards included.

## Notch

On Macs with a notch, FocusKit lives in it and grows out of it. While a session runs or music plays, the time left and the song appear on either side of the camera, and a new song, a break or a finished session slides in beside it without covering the screen. Move the pointer to the top of the screen and it opens:

- **Home** – how long you have focused today, your streak and the last seven days, a tap to start any mode, and either the song playing or the time and your next event.
- **Music** – the cover, the time left in the song and the controls over a backdrop taken from the artwork, or a quick way to start Spotify or Music.
- **Calendar** – the month with a dot for each calendar, and the selected day's events on a timeline, with the one happening now highlighted.

Volume, brightness and charging show up in the notch too, as a slim bar on either side of the camera. Turn on **Replace the macOS indicators** in Settings › Notch and FocusKit handles the volume and brightness keys itself, so only the notch appears. This needs the Accessibility permission, asked once.

At rest the notch matches your Mac's own, so nothing shows until something happens. Choose when it appears in **Settings › Notch**.

## Menu bar

FocusKit keeps a small icon in the menu bar, with the time left while a session runs. Click it to see today, this week and your streak, start any mode with one tap, pause or skip the session, stop a recording, or open FocusKit, Settings, check for updates, restart or quit.

Closing the window does not quit the app. FocusKit leaves the Dock and keeps running in the menu bar and the notch, ready for the next session. Turn this off in **Settings › Focus**.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Switch section | ⌘1 – ⌘4 |
| Start session | ⌘↩ (hold ⌥ to skip the check-in) |
| Pause / resume | Space or ⇧⌘P |
| Skip round or break | ⇧⌘K |
| End session | ⌘. |
| New subject | ⌘N |
| Export lecture as PDF | ⇧⌘E |

## Privacy

There is no account, no analytics and no server. Your library, recordings and settings stay on this Mac. Speech recognition, notes and flashcards run on device. FocusKit only goes online to load map imagery for Flight, which Apple Maps provides, and to check GitHub for a new version, which you can turn off in Settings › Updates.

## Building

Requires macOS 26, Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make run
```

| Command | What it does |
| --- | --- |
| `make run` | Builds a debug copy and opens it |
| `make dmg` | Builds a universal release in `dist/` |

Pushing a tag such as `v0.4.0` builds the disk image on GitHub Actions and publishes the release that the app offers as an update.

## License

FocusKit is free to use for personal, study and other noncommercial purposes under the [PolyForm Strict License 1.0.0](LICENSE). The source is published so you can see how it works and what it does with your data. Modifying it, redistributing it or publishing derived apps is not permitted.

Versions up to 0.3.0 were released under the MIT License.
