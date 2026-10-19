<div align="center">

<img src="assets/swara-mark.png" width="120" alt="Swara logo">

# 🎵 Swara: Offline Music Player

**Play the music on your phone without internet, with automatic metadata and lyrics, plus an analytics dashboard of your listening habits.**

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?style=flat-square&logo=flutter&logoColor=white)
![Release](https://img.shields.io/github/v/release/nekonaru/swara?style=flat-square&color=blue)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)
![Status](https://img.shields.io/badge/Status-Active-brightgreen?style=flat-square)
![CI](https://github.com/nekonaru/swara/actions/workflows/build-apk.yml/badge.svg)

</div>

**English** | [Bahasa Indonesia](README.id.md)

## ✨ About

**Swara** is a lightweight Flutter app that plays music straight from your phone storage - no account, no ads, no internet needed. It scans your collection once, then automatically completes titles, artists, album art, genres, and even lyrics over the internet. Your listening activity is summarized in an analytics dashboard, and everything works fully offline afterwards.

> _"Your music collection, played in peace, even without internet."_

## 🎯 Features

| Feature | Description |
|---------|-------------|
| ▶️ **Offline playback** | Scan and play music directly from phone storage |
| 🔔 **Background playback** | Real Android foreground service with MediaSession: notification and lockscreen controls (play/pause/next/previous) |
| 🔀 **Shuffle and repeat** | Shuffle, repeat off / all / one, plus sleep timer by duration or song count |
| ⏱️ **Mini player** | Always visible on every page; playback speed control from 0.5x to 2x |
| 📝 **Play queue** | Add songs to play next or at the end, reorder and remove |
| 👆 **Multi-select** | Long-press to select many songs, then favorite or add to playlist in bulk |
| 🌐 **Automatic metadata** | Titles, artists, album art, and genres via the iTunes Search API |
| 🎤 **Automatic lyrics** | Fetched via lyrics.ovh, editable manually, Google search fallback |
| ✏️ **Manual editing** | Fix metadata and lyrics per song when auto-fetch gets it wrong |
| 📁 **Folder browsing** | Browse by source folder, hide folders from the library |
| 🔤 **A-Z navigation** | Finger-following letter scrollbar for fast jumps |
| 💿 **Playlists and favorites** | Custom playlists, favorites, recently played |
| 🤖 **Smart auto-playlists** | Daily Mix (25 fresh songs every day) and Unplayed, maintained automatically |
| 🎼 **Synced lyrics** | Line-by-line lyrics that follow the song, with plain view fallback |
| 😴 **Gentle sleep timer** | Volume fades out instead of stopping abruptly |
| 💾 **Backup and restore** | Export and import playlists, favorites, and history as JSON |
| 🖼️ **Playlist covers** | Auto-generated collages from member album art |
| 🏆 **Yearly recap** | Top songs, artists, and hours of the current year, shareable as an image |
| 📋 **Save queue** | Save the play queue as a playlist in one tap |
| 🌙 **Bedtime schedule** | Sleep timer for a fixed clock time every night |
| 🎚️ **Real equalizer** | 9 presets shaping actual playback sound via system DSP |
| 🔍 **Forgiving search** | Finds "faded alan walker" for "faded - alan walker" |
| 🗂️ **Duplicate finder** | Find and remove duplicate songs, keep one per group |
| 🖼️ **Missing covers** | List songs without art with one-tap refetch |
| 📂 **Playlist folders** | Group playlists into folders |
| 🔀 **Merge playlists** | Combine another playlist in, skipping duplicates |
| 🖼️ **Missing lyrics** | List songs without lyrics with one-tap refetch |
| 🎚️ **Crossfade control** | Adjustable 0-12s transition plus custom 5-band EQ |
| 🌑 **AMOLED black** | Pure-black dark theme option |
| 🚀 **Full lists, no Load more** | Every list renders in full while staying smooth, A-Z jump is instant, shuffle covers every song |
| 🎚️ **Speed and pitch** | Playback speed 0.5x to 2.0x plus pitch control with live apply and reset |
| 🧠 **Smart shuffle** | Biases playback toward rarely played and long unplayed songs |
| 🛏️ **Daily sleep schedule** | Auto start a 30 minute sleep timer at a chosen time every day |
| ⚡ **Faster database** | WAL mode, tuned pragmas, and matching indexes so sorting and jumping stay instant |
| 🧹 **History cleanup** | Optional, you-confirmed cleanup of old listening history in Settings |
| ⏱️ **Lyric timing** | Reads the offset tag from .lrc files and lets you nudge lyrics by 100 ms |
| 🔤 **Typo tolerant search** | Finds songs despite swapped or mistyped letters, with a "did you mean" hint |
| 📥 **M3U import/export** | Import playlists from .m3u files, export them back out |
| 🔁 **A-B repeat** | Loop any song segment for practice |
| ✏️ **Bulk edit** | Edit genre and artist across many songs at once |
| 📤 **Share songs** | Share the currently playing info plus audio file |
| 🔥 **Listening streaks** | Day streak and top genre of the month on the dashboard |
| 🔍 **Search** | Real-time search by title, artist, album, folder, or genre, with debounced input |
| 📊 **Dashboard** | Last-7-days chart, top songs and artists, genre and region distribution |
| 🌍 **English and Indonesian UI** | English by default; switch to Bahasa Indonesia in Settings |
| 🎨 **Themes** | Light, dark, or follow system, plus 10 accent colors |

## 📦 Requirements

- **Flutter** 3.47 or newer (stable channel)
- **JDK** 17
- **Android SDK** (API 34+)
- An Android phone or emulator (minimum Android 8.0 / API 26)

### Never used a terminal? Start here

<details>
<summary><b>How to open a terminal on Windows</b></summary>

1. Press the **Windows** key, type `PowerShell`, then press **Enter**
2. A blue window opens. That is where you type commands
3. Every `flutter ...` or `git ...` command in this guide is typed in that window, followed by **Enter**

</details>

## 🚀 Installation

### Option A: Download the APK (easiest)

1. Open the [Releases](https://github.com/nekonaru/swara/releases) page
2. Download the APK matching your device (`app-arm64-v8a-release.apk` for most modern phones, `app-armeabi-v7a-release.apk` for older 32-bit ones)
3. Open it on your phone, allow installs from unknown sources if asked
4. Allow audio access when the app first opens

### Option B: Build from source (for development / to read or change the code)

**1. Get the project code**

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

**2. Install dependencies and verify**

```bash
flutter pub get
flutter analyze
```

`flutter analyze` must report **No issues found**.

**3. Build the APK**

```bash
flutter build apk --release
```

The result is at `build/app/outputs/flutter-apk/app-release.apk`.

## 🖥️ Usage

**First launch:**
1. Allow audio access when asked
2. The app scans your music once and saves it to a local database
3. Missing metadata and lyrics are fetched automatically in small batches

**Everyday use:**
- Browse **Library** (Songs, Albums, Artists, Folders, Genres tabs, configurable)
- Tap a song to play; use the mini player to control from any page
- Swipe down on the player to minimize it
- Long-press songs for multi-select (favorite or add to playlist in bulk)
- Open **Dashboard** to see your listening statistics

## 🌍 Display Language

The app UI (menus, buttons, messages, and settings) is available in **English** (default) and **Bahasa Indonesia**.

1. Open **Settings**
2. Under **Language**, pick **English** or **Bahasa Indonesia**
3. The choice is remembered between sessions

## 🗂️ Project Structure

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

**Adding a new user-facing string:**
1. Add the key to `lib/l10n/app_en.arb` (English) and `lib/l10n/app_id.arb` (Indonesian)
2. Run `flutter gen-l10n`
3. Use it via `AppLocalizations.of(context)!.yourKey`

## 🧪 Testing

There is no test suite yet. Static verification before every push:

```bash
flutter analyze
```

It must report **No issues found** (zero errors, zero warnings).

## ❓ FAQ

<details>
<summary><b>Music stops when the app goes to background?</b></summary>

Make sure battery optimization is turned off for Swara (Autostart / unrestricted background on XOS, MIUI, and similar skins), and that notification permission is granted.

</details>

<details>
<summary><b>Some songs show "Unknown Artist" or have no lyrics?</b></summary>

Auto-fetch depends on public databases (iTunes, lyrics.ovh). Local or indie songs are often missing there. Use Edit Metadata / Edit Lyrics on the song to fix it manually.

</details>

<details>
<summary><b>How do I change the language?</b></summary>

Settings, section **Language**, pick English or Bahasa Indonesia. English is the default.

</details>

## 👤 Author

<div align="center">

| [![Nicolas Dwi Dharma](https://github.com/github.png?size=100)](https://github.com/nekonaru) |
|:---:|
| **Nicolas Dwi Dharma** |
| [github.com/nekonaru](https://github.com/nekonaru) |

</div>

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

<div align="center">

Made by **Nicolas Dwi Dharma**

*Star this repo if this project helps you!*

</div>
