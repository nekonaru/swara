<div align="center">
  <img src="assets/swara-mark.png" alt="Swara logo" width="120" />
  <h1>Swara: Offline Music Player</h1>
  <p><b>Play the music on your phone without internet, with metadata and lyrics fetched on demand,<br/>
  plus an analytics dashboard of your listening habits.</b></p>

  <a href="https://github.com/nekonaru/swara/releases"><img src="https://img.shields.io/github/v/release/nekonaru/swara?style=flat-square&color=blue" alt="Release" /></a>
  <a href="https://github.com/nekonaru/swara/actions/workflows/build-apk.yml"><img src="https://github.com/nekonaru/swara/actions/workflows/build-apk.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Platform" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
  <img src="https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square" alt="Status" />
</div>

<br />

**English** | [Bahasa Indonesia](README.id.md)

> [!NOTE]
> Swara plays music straight from your phone storage. Internet is only used when you start a metadata or lyrics scan yourself. A scan never starts on its own and can be stopped at any time.

---

## Table of Contents

- [About](#about)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Display Language](#display-language)
- [Data Sources](#data-sources)
- [Project Structure](#project-structure)
- [Development](#development)
- [Testing](#testing)
- [Continuous Integration](#continuous-integration)
- [FAQ](#faq)
- [Author](#author)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## About

**Swara** is a lightweight Flutter app that plays music straight from your phone storage - no account, no ads, no internet needed. It scans your collection once, then completes titles, artists, album art, genres and even lyrics over the internet whenever you start a scan yourself. A scan never starts on its own and can be stopped at any time. Your listening activity is summarized in an analytics dashboard, and everything works fully offline afterwards.

> _"Your music collection, played in peace, even without internet."_

---

## Features

### Playback

| Feature | Description |
|---------|-------------|
| **Offline playback** | Scan and play music directly from phone storage |
| **Background playback** | Real Android foreground service with MediaSession: notification and lockscreen controls (play/pause/next/previous) |
| **Shuffle and repeat** | Shuffle, repeat off / all / one, plus sleep timer by duration or song count |
| **Mini player** | Always visible on every page; playback speed control from 0.5x to 2x |
| **Smart shuffle** | Biases playback toward rarely played and long unplayed songs |
| **A-B repeat** | Loop any song segment for practice |

### Sound

| Feature | Description |
|---------|-------------|
| **Real equalizer** | 9 presets shaping actual playback sound via system DSP |
| **Crossfade control** | Adjustable 0-12s transition plus custom 5-band EQ |
| **Speed and pitch** | Playback speed 0.5x to 2.0x plus pitch control with live apply and reset |

### Sleep Timer

| Feature | Description |
|---------|-------------|
| **Gentle sleep timer** | Volume fades out instead of stopping abruptly |
| **Bedtime schedule** | Sleep timer for a fixed clock time every night |
| **Daily sleep schedule** | Auto start a 30 minute sleep timer at a chosen time every day |

### Metadata and Lyrics

| Feature | Description |
|---------|-------------|
| **On-demand metadata** | Titles, artists, album art, and genres via the iTunes Search API, from a scan you start yourself |
| **Stop any scan** | Metadata scans never start on their own, and every one of them can be stopped halfway with nothing lost |
| **Per-song metadata refresh** | "Scan metadata" in the song menu refetches one song from the internet |
| **On-demand lyrics** | Fetched via lrclib with lyrics.ovh as fallback, editable manually, Google search fallback |
| **Manual editing** | Fix metadata and lyrics per song when the scan gets it wrong |
| **Synced lyrics** | Line-by-line lyrics that follow the song, with plain view fallback |
| **Lyric timing** | Reads the offset tag from .lrc files and lets you nudge lyrics by 100 ms |

### Library and Search

| Feature | Description |
|---------|-------------|
| **Multi-select** | Long-press to select many songs, then favorite or add to playlist in bulk |
| **Folder browsing** | Browse by source folder, hide folders from the library |
| **A-Z navigation** | Finger-following letter scrollbar for fast jumps |
| **Search** | Real-time search by title, artist, album, folder, or genre, with debounced input |
| **Forgiving search** | Finds "faded alan walker" for "faded - alan walker" |
| **Typo tolerant search** | Finds songs despite swapped or mistyped letters, with a "did you mean" hint |
| **Share songs** | Share the currently playing info plus audio file |

### Library Maintenance

| Feature | Description |
|---------|-------------|
| **Duplicate finder** | Find and remove duplicate songs, keep one per group |
| **Missing covers** | List songs without art with one-tap refetch |
| **Missing lyrics** | List songs without lyrics with one-tap refetch |
| **Bulk edit** | Edit genre and artist across many songs at once |

### Queue and Playlists

| Feature | Description |
|---------|-------------|
| **Play queue** | Add songs to play next or at the end, reorder and remove |
| **Save queue** | Save the play queue as a playlist in one tap |
| **Playlists and favorites** | Custom playlists, favorites, recently played |
| **Smart auto-playlists** | Daily Mix (25 fresh songs every day) and Unplayed, maintained automatically |
| **Playlist covers** | Auto-generated collages from member album art |
| **Playlist folders** | Group playlists into folders |
| **Merge playlists** | Combine another playlist in, skipping duplicates |
| **M3U import/export** | Import playlists from .m3u files, export them back out |

### Statistics

| Feature | Description |
|---------|-------------|
| **Dashboard** | Last-7-days chart, top songs and artists, genre and region distribution |
| **Yearly recap** | Top songs, artists, and hours of the current year, shareable as an image |
| **Listening streaks** | Day streak and top genre of the month on the dashboard |

### Data and Backup

| Feature | Description |
|---------|-------------|
| **Backup and restore** | Export and import playlists, favorites, and history as JSON |
| **History cleanup** | Optional, you-confirmed cleanup of old listening history in Settings |

### Appearance and Language

| Feature | Description |
|---------|-------------|
| **English and Indonesian UI** | English by default; switch to Bahasa Indonesia in Settings |
| **Themes** | Light, dark, or follow system, plus 10 accent colors |
| **AMOLED black** | Pure-black dark theme option |

### Performance

| Feature | Description |
|---------|-------------|
| **Full lists, no Load more** | Every list renders in full while staying smooth, A-Z jump is instant, shuffle covers every song |
| **Faster database** | WAL mode, tuned pragmas, and matching indexes so sorting and jumping stay instant |
| **Smooth on huge libraries** | Search, sorting, and single-row updates run off the main thread, with cached derived views and hoisted regexes, so nothing stutters |

---

## Requirements

| Dependency | Minimum Version | Notes |
|------------|-----------------|-------|
| **Flutter** | 3.47 | Stable channel, required only to build from source |
| **JDK** | 17 | Required only to build from source |
| **Android SDK** | API 34+ | Required only to build from source |
| **Android device or emulator** | Android 8.0 (API 26) | Required to run the app |

> [!TIP]
> If you only want to use the app, you do not need Flutter, JDK, or the Android SDK. Download the APK from the [Releases](https://github.com/nekonaru/swara/releases) page instead.

### Never used a terminal? Start here

<details>
<summary><b>How to open a terminal on Windows</b></summary>

1. Press the **Windows** key, type `PowerShell`, then press **Enter**
2. A blue window opens. That is where you type commands
3. Every `flutter ...` or `git ...` command in this guide is typed in that window, followed by **Enter**

</details>

---

## Installation

### Option A: Download the APK (easiest)

1. Open the [Releases](https://github.com/nekonaru/swara/releases) page
2. Download the APK matching your device (`app-arm64-v8a-release.apk` for most modern phones, `app-armeabi-v7a-release.apk` for older 32-bit ones)
3. Open it on your phone, allow installs from unknown sources if asked
4. Allow audio access when the app first opens

> [!IMPORTANT]
> Grant audio access when asked, otherwise Swara cannot see your music. Grant notification permission as well so background playback controls can appear.

### Option B: Build from source (for development / to read or change the code)

#### 1. Get the project code

<details>
<summary><b>I have Git installed</b></summary>

```bash
git clone https://github.com/nekonaru/swara.git
cd swara
```

</details>

<details>
<summary><b>I don't have Git</b></summary>

1. Open the repository page on GitHub
2. Click the green **`Code`** button, choose **`Download ZIP`**
3. Extract the ZIP to a folder of your choice
4. In the terminal, go into the extracted folder, for example:

```bash
cd Downloads/swara-main
```

</details>

#### 2. Install dependencies and verify

```bash
flutter pub get
flutter analyze
```

> [!IMPORTANT]
> `flutter analyze` must report **No issues found**.

#### 3. Build the APK

```bash
flutter build apk --release
```

The result is at `build/app/outputs/flutter-apk/app-release.apk`.

---

## Usage

### First launch

1. Allow audio access when asked
2. The app scans your music once and saves it to a local database
3. Start a metadata scan from the library menu or Settings; it fetches in small batches and you can stop it at any time

> [!NOTE]
> Metadata and lyrics scans only run when you start them. Once they finish, everything works offline.

### Everyday use

- Browse **Library** (Songs, Albums, Artists, Folders, Genres tabs, configurable)
- Tap a song to play; use the mini player to control from any page
- Swipe down on the player to minimize it
- Long-press songs for multi-select (favorite or add to playlist in bulk)
- Open **Dashboard** to see your listening statistics

---

## Display Language

The app UI (menus, buttons, messages, and settings) is available in **English** (default) and **Bahasa Indonesia**.

1. Open **Settings**
2. Under **Language**, pick **English** or **Bahasa Indonesia**
3. The choice is remembered between sessions

---

## Data Sources

Swara only goes online when you start a scan yourself. The public services it uses are:

| Purpose | Source |
|---------|--------|
| Titles, artists, album art, genres | iTunes Search API |
| Lyrics | lrclib, with lyrics.ovh as fallback |
| Lyrics last resort | Google search fallback |

> [!NOTE]
> These are public databases, so local or indie songs are often missing there. Use Edit Metadata / Edit Lyrics on the song to fix it manually.

---

## Project Structure

```
swara/
├── lib/
│   ├── main.dart                 # entry point, providers, MaterialApp + locale
│   ├── l10n/
│   │   ├── app_en.arb            # English strings (source of truth)
│   │   ├── app_id.arb            # Indonesian strings
│   │   └── gen/                  # generated localizations (do not edit by hand)
│   ├── models/                   # Song, ListeningEntry
│   ├── providers/                # library, playlist, theme, language state
│   ├── screens/                  # all pages (library, player, dashboard, ...)
│   ├── services/                 # player, database, scanner, metadata, audio handler
│   ├── utils/                    # formatting, song options menu, transitions
│   └── widgets/                  # mini player, sleep timer, scrollbar, ...
├── l10n.yaml                     # localization config
├── android_res_extra/            # notification icons drawn into the APK by CI
├── .github/
│   └── workflows/
│       ├── build-apk.yml         # CI: build APK on every push to main
│       └── build.yml             # CI: build APK + draft GitHub release
├── pubspec.yaml
├── LICENSE
├── README.md                     # main documentation (English)
└── README.id.md                  # documentation (Bahasa Indonesia)
```

---

## Development

### Adding a new user-facing string

1. Add the key to `lib/l10n/app_en.arb` (English) and `lib/l10n/app_id.arb` (Indonesian)
2. Run `flutter gen-l10n`
3. Use it via `AppLocalizations.of(context)!.yourKey`

> [!WARNING]
> Files inside `lib/l10n/gen/` are generated. Do not edit them by hand, change the `.arb` files and run `flutter gen-l10n` instead.

---

## Testing

Verification before every push, both must be clean:

```bash
flutter analyze
flutter test
```

| Check | Requirement |
|-------|-------------|
| `flutter analyze` | Must report **No issues found** (zero errors, zero warnings) |
| `flutter test` | Must pass the full suite |

Lints are enforced through `analysis_options.yaml` (flutter_lints plus `prefer_single_quotes` and `sort_child_properties_last`).

---

## Continuous Integration

| Workflow | Purpose |
|----------|---------|
| `build-apk.yml` | Build APK on every push to main |
| `build.yml` | Build APK and create a draft GitHub release |

Notification icons from `android_res_extra/` are drawn into the APK by CI.

---

## FAQ

<details>
<summary><b>Music stops when the app goes to background?</b></summary>

Make sure battery optimization is turned off for Swara (Autostart / unrestricted background on XOS, MIUI, and similar skins), and that notification permission is granted.

</details>

<details>
<summary><b>Some songs show "Unknown Artist" or have no lyrics?</b></summary>

Auto-fetch depends on public databases (iTunes, lrclib, lyrics.ovh). Local or indie songs are often missing there. Use Edit Metadata / Edit Lyrics on the song to fix it manually.

</details>

<details>
<summary><b>How do I change the language?</b></summary>

Settings, section **Language**, pick English or Bahasa Indonesia. English is the default.

</details>

---

## Author

| [![Nicolas Dwi Dharma](https://github.com/github.png?size=100)](https://github.com/nekonaru) |
|:---:|
| **Nicolas Dwi Dharma** |
| [github.com/nekonaru](https://github.com/nekonaru) |

---

## Disclaimer

Swara is an independent open-source project and is not affiliated with or endorsed by Apple, lrclib, lyrics.ovh, or Google. Metadata and lyrics come from public databases and may be incomplete or inaccurate, which is why every song can be edited manually.

---

## License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.
