# Changelog

## v4.13.1

Patch release after review: safer backup restore, dependable built-in rules, and consistent Android Auto browsing.

## Bug fixes

- **Restoring a backup no longer converts a hand-curated playlist** with the same name into a smart playlist or replaces its members.
- **Built-in playlists with a missing rule are repaired** instead of being skipped forever, including rows restored from older backups.
- **Android Auto root paging and hidden folders behave correctly.** A hidden folder or its descendants cannot be browsed in the car.
- **Voice commands with artist or album metadata work** even when the spoken query is empty.
- **Daily Mix reshuffle refreshes its collage**, and an invalid rule limit is rejected instead of silently becoming unlimited.
- **Smart rebuilds during playback skip unnecessary work** when membership is unchanged.

## v4.13.0

Large browse and playlist reliability release: full Android Auto paging with voice playback, and fixes that make built-in smart playlists dependable, with no new dependency.

## New features

- **Android Auto recent category and paging.** Large libraries load 50 items per page, and voice commands such as "play artist" start a matching song without replacing the current queue.

## Improvements

- **Built-in smart playlists always exist.** Fresh installs and deleted built-ins are recreated, and a renamed built-in keeps its editable rule.
- **Smart membership respects hidden folders and limits.** A rule with a limit returns the requested number of visible songs.
- **Smart playlist art refreshes** after a rule edit, manual refresh, or library change.
- **Backup restore applies the backed-up rule** to an existing same-named smart playlist before rebuilding members.

## Bug fixes

- **Forgotten Favorites includes never-played favorites** again.
- **Smart rule editing rejects invalid numeric conditions** instead of silently storing zero.
- **A failed smart rebuild during playback is logged** instead of raising an unhandled error.
- **Actionable snackbars stay available** until their own snackbar closes.
- **An empty-library snapshot names the real cause** instead of saying there are no snapshots.

## v4.12.0

Large playlist and reliability release: editable rule-based smart playlists, plus fixes from the latest native audit, with no new dependency.

## New features

- **Rule-based smart playlists.** Create a playlist, define conditions on title, artist, album, genre, favorite, play count, last played, date added or duration, then let the app maintain membership offline. The built-in Daily Mix, Unplayed and Forgotten Favorites become editable rules.

## Improvements

- **Smart playlist rules survive backup and restore.** Rules travel in the v3 payload and members are rebuilt after import.
- **One canonical path function.** Backup identity normalization lives in one shared utility instead of two copies.

## Bug fixes

- **Leaving Search during isolate startup no longer raises an unhandled error.**
- **Taking a snapshot on an empty library now shows feedback** instead of silently doing nothing.
- **Tag write results no longer report a misleading fallback message**, and the queue refreshes even for a database-only edit.
- **Dashboard invalidation happens after the playback write**, so a just-played song leaves the never-played list immediately.
- **Actionable snackbars reset when they close**, so later messages replace them instead of queueing.
- **Forced and automatic snapshots no longer race** on the same filename.

## v4.11.0

Large offline data release: local snapshots, tag writeback, and several native reliability fixes, with no new dependency.

## New features

- **Local snapshots.** The app keeps up to three recent JSON snapshots in app-private storage, taken on a daily timer and when the app is backgrounded. Settings can list, restore and delete them, and offers a one-time restore if the library is empty.
- **Write tags to the music file.** The Edit Metadata screen can also write title, artist and album to MediaStore after the usual consent prompt. If the OS refuses, the library edit still lands and the message says so.

## Improvements

- **API 10 rename uses MediaStore directly** instead of calling a method introduced in API 11, so real rename works on Android 10 with a modern target SDK.
- **Dashboard invalidates on playback.** Marking a song played now clears the cached never-played list immediately.
- **Alias normalization is shared.** Backup identity uses one canonical path function, so paths with escapes or duplicate slashes still resolve after a rename.
- **Search isolate lifecycle is safer.** A dispose during startup kills the new isolate instead of leaking it.
- **CI rejects blank signing secrets**, not just missing ones.

## Bug fixes

- **An actionable snackbar is no longer hidden** by unrelated messages, so the update retry button stays available.
- **A failed v15 alias migration no longer breaks backup export.**
- **Cached dashboard songs keep their full fields**, so playing from a cached rank tile still works with lyrics and artwork.

## v4.10.0

Large performance and reliability release: persistent search isolation, a full dashboard cache, rename-aware backups, and safer native update paths, with no new permission or dependency.

## Improvements

- **Search keeps one long-lived isolate.** Haystacks are prepared once per library version and filter; each keystroke sends only the query text, so typing stays light on large libraries.
- **Dashboard revisits use the cache.** Summary numbers, charts, rank lists, hidden-song filtering and compact song entries are cached for ten minutes and invalidated by an epoch on every data change.
- **Backups remember renamed paths.** Schema v15 keeps previous file identities so a backup made before a real rename can still restore tags, lyrics, playlists and history.
- **Snackbars no longer stack anywhere.** Every message replaces the previous one, lasts two seconds, and can be closed immediately.
- **CI refuses incomplete signing secrets.** A partial key configuration fails the build instead of silently publishing a debug-signed APK.

## Bug fixes

- **Android 10 rename no longer calls an API 30 method**, so it cannot crash or hang on a rename request.
- **A failed library update after a rename now reloads the library** and reports that the file itself was renamed.
- **Local covers that exist but cannot decode fall back to embedded art** instead of leaving a blank row.
- **Storage permission is only requested on Android 10 and below**, so scoped-storage users still get the correct MediaStore consent prompt.
- **The update hint now explains the backup, uninstall, reinstall and restore steps** needed to move from an older debug-signed install.

## v4.9.0

Large usability and reliability release: short dismissible feedback, real file rename where the OS allows it, and stable release signing for direct updates.

## New features

- **Real file rename.** "Rename song" now renames the music file on disk through MediaStore or the legacy filesystem path, then updates the library in one operation. If the OS refuses, the app falls back to a title-only edit and says so clearly.

## Improvements

- **Feedback no longer blocks the UI.** All snackbars last two seconds, show a close icon, and replace the previous message instead of stacking.
- **Release signing is pinned in CI.** A single key is decoded from GitHub Secrets, so future in-app updates keep the same certificate.
- **Update dialog explains the one-time move.** Users on older debug-signed installs see why a single uninstall may be needed before direct updates work.
- **Android Auto taps preserve the queue.** Browse leaves play the chosen song without replacing the current queue.
- **Artwork fallback recovers after a cache clear.** A failed cover reload retries embedded art instead of staying blank.

## Bug fixes

- **In-app update no longer fails from changing signatures** on releases built after this version.
- **Renamed files survive uninstall and reinstall** because the real file, not only the database title, is changed.
- **Old queue IDs cannot play the wrong song** after a reorder or a cold restore.

## v4.8.0

Large native integration release: a real Android Auto browse tree and a next-up line in the home widget, with no new permission or dependency.

## New features

- **Android Auto browse tree.** Playlists, folders, songs and the current queue are browsable offline, with tappable leaves that play the intended song.
- **Next up on the widget.** The home widget now shows the next title in play order and hides the line at the end of the queue.

## Improvements

- **Queue IDs are verified before playback.** A stale slot can no longer play the wrong song after a reorder or a cold restore; the file path remains the source of truth.
- **Playlist replacement preserves order.** Auto playlists write positions in one transaction and dedupe members.
- **Lyric offset writes are serialized.** A slow nudge can no longer land after a timing reset.
- **Cover existence checks are cached per path.** Duplicate album and playlist art no longer repeats disk I/O for every visible row.
- **Restored tags keep their scanned flag only when a tag was actually restored.**

## Bug fixes

- **Android Auto browse was empty.** The media handler now supplies real children instead of returning an empty list.
- **The queue title follows the app language** on Android Auto and lockscreen instead of a hard-coded English string.

## v4.7.0

Feature and performance release: named bookmarks, one-tap lyric reset, and a lighter backup and playback path, with no new permission.

## New features

- **Bookmark labels can be renamed.** Saved playhead positions are now genuinely named instead of showing only a duration.
- **Lyric timing reset.** A single button clears a saved correction and returns to the original file offset.

## Improvements

- **Backup export is batched.** Per-song extras are read in bulk instead of three queries per song, so large libraries export much faster.
- **Backup identity is indexed.** Path and basename matching builds one lookup table instead of scanning local songs for every imported row.
- **Auto playlists replace contents in bulk.** One delete and one insert replace thousands of single-song writes and notifications.
- **The widget stops churning during playback.** Ordinary position ticks no longer trigger a widget rebuild every 1.5 seconds.
- **Artwork probing skips covered songs.** Rows with a local or remote cover no longer query MediaStore on the first scroll.
- **Warm database opens skip existing indexes.** Eleven idempotent statements are no longer issued on every launch.
- **Import reports use one message.** Restored and skipped counts no longer hide each other behind successive snackbars.
- **Restored tags keep their scanned flag.** A later missing-metadata scan will not overwrite tags that came from a backup.

## Bug fixes

- **Song-only v3 backups import correctly** instead of being rejected as having no matching entries.
- **Metadata counts reflect real changes.** An unchanged local library no longer reports restored metadata.
- **Bookmark taps ignore a track change** instead of seeking the new song to the old song's position.
- **Pending lyric corrections reach the database** before an edit reload or an exit, and are retried if a write fails.

## v4.6.0

Large data and native polish release: stable-identity backup, a user-visible save location, and a deeper accessibility pass, with no new permission.

## New features

- **Backup format v3.** Manual tags, plain lyrics, synced LRC, timing corrections, favorites and bookmarks are matched by normalized file path with a basename and duration fallback, so a restore works on another device even when MediaStore ids change.
- **Save backups where you choose.** Save to file now opens the system file picker and writes to the location you pick, instead of an app-private folder the Files app cannot reach.

## Improvements

- **Backup summaries report what was restored.** The import result now counts matched songs, metadata, lyrics, synced lines, offsets and bookmarks.
- **Reduce animations is honoured across the app.** Player art and play controls, EQ bars, mini player, list switches and lyric scrolling now follow the OS setting.
- **Dashboard album ranking is indexed.** A julianday expression index avoids a full listening-history scan on each cache miss.
- **Lyric timing and bookmarks are more robust.** Pending corrections flush on exit or song change, lyric loads use generations, and bookmarks stay bound to the song that opened the sheet.

## Bug fixes

- **Lyric timing is no longer lost** when leaving the player quickly or when an edit arrives during a load.
- **Lyric edits refresh an open player** instead of leaving stale text or a stale offset.
- **Bookmark list no longer flashes empty** after a save or delete, and a notification track change cannot attach a bookmark to the wrong song.
- **Importing a corrected LRC keeps the saved timing correction.**
- **The lyric timing row and notification setting fit 320dp with large text.**

## v4.5.0

Large feature and native polish release: persistent lyric timing, local LRC files, song bookmarks and album statistics, with deeper accessibility support.

## New features

- **Lyric timing correction is remembered.** The 100 ms nudge is saved per song, survives a restart, and clears when fresh lyrics are fetched.
- **Local .lrc files work offline.** Import a sidecar file from the lyrics editor or share the stored synced lyrics back out.
- **Song bookmarks.** Save up to 20 playhead positions per song and jump to them from the player.
- **Top albums on the dashboard.** Albums are ranked by listening time over the last 30 days using existing history data.

## Improvements

- **Accessibility text is no longer reduced in lists.** Row heights now grow with the effective text scale instead of capping row text at 1.5x.
- **Player controls fit small screens.** The transport row wraps and uses 44dp touch targets on narrow devices.
- **EQ controls fit large text.** Band labels and gain readouts scale and the visualizer grows with the text scale.
- **Reduce animations is honoured more widely.** Marquee text and the playing indicator stop animating when the OS requests reduced motion.
- **Notification access can be fixed later.** A denied prompt remains askable and Settings opens the system app settings when needed.

## Bug fixes

- **The home widget no longer keeps a fake playing clock** after the app is killed, because cold start now forces the real paused state to the widget.

## v4.4.0

Performance and visual quality release: faster startup, readable default text and contrast in both themes, with no new features.

## Improvements

- **Startup drops the artificial wait.** The 600 ms boot floor and a longer crossfade are gone, so the first usable screen arrives sooner.
- **Cold restore no longer blocks the first frame.** Queue and audio source restore now runs after the boot gate while external actions still wait for readiness.
- **Collection work waits for its tab.** The collection screen no longer syncs auto playlists and decodes collages on the first frame.
- **Database opens once.** A memoized init future removes duplicate open and migration work during cold start.
- **Text scale follows a normal baseline.** Small is 0.85, normal is 1.0 and large is 1.15, with an upgrade migration that preserves the previous choice.
- **Primary text and tabs are easier to read.** Song, album and collection titles, chart labels, EQ labels and tab labels now use larger native sizes.
- **Buttons and empty charts follow the theme.** Bespoke corner radii are gone and the empty chart ring uses a neutral tone in both themes.

## Bug fixes

- **Dark theme text is no longer black.** ThemeData now derives the text colors from the active color scheme instead of an inverted custom theme.
- **Lyrics refresh keeps manual metadata.** Titles, artists, albums and artwork edited by the user survive a lyrics fetch.
- **Metadata backoff no longer drops a batch.** A rate limit wait retries the same batch instead of skipping it.
- **M3U imports resolve relative paths.** Dot segments are canonicalized and duplicate playlist names get a numeric suffix.
- **EQ sliders follow the active preset.** Opening the equalizer from another surface no longer shows a stale curve.
- **Dashboard totals refresh.** New listening entries invalidate the aggregate cache immediately.
- **Lyrics found message accepts synced lines.** A synced only result is no longer reported as not found.

## v4.3.2

Stability release: fixes deep audit findings in playback, backup and performance, with no new features.

## Improvements

- **Art cache tools stay light.** Measuring and clearing covers no longer decompress every lyric, and clearing also drops remote cover references so the cache does not refill on the next scroll.
- **Song lists keep a stable order.** Paged browsing no longer silently reorders after 60 seconds.
- **Artwork probing shares one MediaStore client.** The first scroll through a large library does less native setup work.
- **Quick Settings tile releases its controller callback** when the media session is suspended.

## Bug fixes

- **Empty playback queues stop audio.** Play all on an empty list and deleting the last song now pause both players, so no orphaned track keeps playing.
- **Cold resume restores the sound again.** The first play after reopening reattaches the equalizer and loudness instead of playing dry until the next song.
- **Notification seeks persist immediately.** Seeking from the notification or Android Auto now guards crossfade and saves the position at once.
- **Media session highlights the right song.** The queue index is clamped while the queue window catches up, and custom actions publish once instead of twice.
- **Crossfade releases its effect callback.** The standby player no longer keeps a listener after release, and per song volume trims are reapplied to the correct player after a settings reload.
- **Playlist removals update immediately.** Removing a song no longer leaves the old tile on screen until the screen is reopened.
- **Backup restores report honest results.** An already existing playlist is a valid no-op instead of a failure, and restored listening times no longer shift to the wrong hour.
- **Failed scans stay retryable.** A denied or failed device scan no longer blocks automatic retry for 30 minutes.

## v4.3.1

Stability release: fixes visual and functional regressions reported after v4.0, with no new features.

## Bug fixes

- **Splash no longer shows two different marks.** The Flutter splash now uses the same flat cream panpipe as the native splash, so the handoff is one continuous glyph.
- **The brand glyph is no longer painted behind the whole app.** A splash-only background keeps the window background plain navy after startup and on legacy devices.
- **Onboarding no longer crashes on first frame.** The page indicator now guards the controller before the PageView attaches, and restored page jumps are deferred until it is ready.
- **Onboarding text scrolls at large accessibility sizes** instead of being clipped on small screens.
- **In-app equalizer sheet scrolls.** All presets, sliders and the save button are reachable on ordinary phones.
- **Loudness and favorite state refresh correctly** after a backup restore and from the notification action.
- **Native typography and button sizing are restored.** Material 3 text sizes and default button heights replace the compact overrides that made the UI look cramped.

## v4.3.0

Android Auto is completed with real browse playback, plus a new offline search mode and audit fixes.

## New features

- **Search by lyrics.** A new Lyrics filter matches the stored, timestamp-stripped text of every song, so a remembered line can find its song without a network request.

## Improvements

- **Android Auto browse works end to end.** Tapping a song in Auto, Wear, or Assistant now starts it through `playFromMediaId`, using the same stable slot id as the local queue.
- **External media clients can connect.** The signature-level permission was removed from the media service and button receiver so Android Auto and Wear can bind.
- **Notification labels follow the locale.** Shuffle and repeat labels are now localized like sleep and favorite.

## Bug fixes

- **Restored playback settings are checked against the local library.** Song ids from a backup are validated before a gain or skip setting is applied, preventing wrong-song overrides.
- **Factory EQ presets apply after a backup restore.** Rock, Jazz and the other built-in curves take effect immediately.
- **Favorite from the notification survives a cold start.** The action waits for playback restore before toggling the current song.

## v4.2.0

New native integrations plus a deep audit of playback and restore behavior.

## New features

- **Android Auto.** Swara is declared as a media app for Android Auto, so browsing and playback controls work from the car through the existing MediaSession.
- **Custom notification actions.** The media notification now offers a 15 minute sleep timer and a favorite toggle alongside the existing shuffle, repeat and transport controls.

## Improvements

- **Named EQ curves survive restarts.** The active saved preset's gains are resolved correctly on startup and after a backup restore, and reach the DSP immediately.
- **Playback settings apply immediately.** Editing a song's gain or restoring a backup now updates the audible player instead of waiting for the next track.

## Bug fixes

- **Aborted crossfades restore volume.** Toggling crossfade off, setting an A-B loop, or editing the queue mid-fade no longer leaves the music quiet.
- **Cold-start resume respects the saved volume trim.** The restored song is re-resolved after the queue is rebuilt.
- **Cancelling an update is not an error.** The failure snackbar no longer appears after a deliberate Cancel tap.
- **Restore counts are honest.** Favorites already set are not counted as newly restored.
- **Per-player maps stay bounded.** Trims and effect-session flags are dropped when a crossfade player is released.

## v4.1.1

Optimization release: existing features start faster, scroll more smoothly and behave more natively, with no new features added.

## Improvements

- **Library loads with less memory.** Gzipped lyrics are decoded in an isolate from a compact id-to-text map instead of copying the whole song table across twice.
- **Settings reacts narrowly.** The library scanning section now watches only the six fields it uses, so metadata scans no longer rebuild the entire settings tree.
- **EQ status is live.** The Active/Unavailable label follows the actual DSP state while Settings stays open.
- **Thumbnails write without fsync.** Cover extraction no longer forces a disk sync per song, reducing first-scroll jank.

## Bug fixes

- **Install permission no longer dead-ends.** After granting unknown-app installs, a Retry action installs the already downloaded APK; a successful install deletes the cached file.
- **Cancel does not pop an extra route.** The update dialog's Cancel handler is guarded and no longer reports a user cancellation as a failure.
- **Import errors are accurate.** A malformed backup no longer claims that no songs matched.
- **Permission prompts wait for the intro crossfade.** They no longer overlay the splash handoff.
- **Player speed chip meets the 48 dp target** and aligns with its sibling controls.

## v4.1.0

Big update: per-song and per-folder playback tuning, plus a full preferences backup, backed by another deep native audit.

## New features

- **Playback settings per song and per folder.** Set a volume trim and skip intro/outro points for one song, or define folder defaults that songs inherit. Overrides survive rescans and take effect immediately.
- **Back up your preferences.** Named EQ presets, the active curve, crossfade, speed and pitch, theme and other playback preferences are now included in backups and can be restored from a JSON file directly in Settings.

## Improvements

- **Quick Settings tile is discoverable.** Settings now explains how to add the tile, and the tile reconnects automatically if the playback service restarts.
- **Named EQ curves stay distinct.** Editing a saved curve no longer overwrites the standalone Custom curve, and reselecting a saved curve keeps your edits.
- **MediaSession highlights the right song.** The active queue item is republished together with the window, so external controllers never point at the wrong track.

## Bug fixes

- **Sleep stop no longer plays an extra song.** A pending sleep stop cancels the crossfade before the next track is brought in.
- **Route and pause volume handling is consistent.** All volume writes go through one trim-aware chain, including sleep stop and standby players.
- **Backups from older versions still import.** Version checking now accepts older formats instead of rejecting every v1 backup.

## v4.0.0

Major release: a smoother, seamless intro and two new native-feeling features, backed by a deep audit of playback and cache behavior.

## New features

- **Named EQ presets.** Save, name, recall, rename and delete multiple 5-band curves. The active curve survives restarts, and the factory presets remain untouched.
- **Quick Settings playback tile.** Play and pause from Android's notification shade with the live track title and state. The tile talks directly to the MediaSession and keeps working with the app backgrounded.

## Improvements

- **Seamless intro.** The mark is on screen from the first frame, the native splash crossfades into it, and one gate fades straight into Home or onboarding with no unbranded spinner.
- **Smooth, accessible motion.** Entrance animations use paint-only transforms, reduce-motion is honoured everywhere through one helper, and onboarding has continuous dots, responsive layout and page progress that survives Back.
- **Permissions after the intro.** Audio and notification prompts are asked once after onboarding, never over the splash animation.

## Bug fixes

- **Headset unplug is handled once.** Route changes go through a single forced-pause path, so the UI and widget stay in sync and cannot resume behind a fired sleep timer.
- **Notification pause cannot be cancelled by a fade.** An explicit pause or stop now forces the pause even while a manual fade is running.
- **Crossfade setting survives a restart.** The enabled flag is persisted like the other playback preferences.
- **Clear art cache clears everything.** Remote covers, their memory indexes and the image cache are dropped along with embedded art.
- **Bulk scans respect the API backoff.** Parallel batches wait out a 429 before continuing instead of hammering the service.

## v3.12.3

Audit release: remaining correctness, accessibility and design gaps in the existing features are closed, with no new features added.

## Improvements

- **Shared type scale.** A small Material 3 text theme now defines headings, titles and captions, and cards use the shared 16 dp radius.
- **Clearer in-flight states.** Search shows a progress bar, the duplicate counter says it is loading, and history errors offer a Retry button.
- **Accessible controls.** Remaining icon buttons have localized tooltips, the tab visibility toggle exposes its checked state, and album art announces its View lyrics action.
- **Theme-aware charts.** Dashboard chart palettes, the streak card and status dots now follow the active color scheme.

## Bug fixes

- **Permissions are remembered only after the prompts return.** A failed request no longer suppresses the prompts on every later launch.
- **Updates cannot start twice.** The About action is guarded and disabled while a check or download is in flight, and Cancel dismisses the dialog immediately.
- **Bulk delete reports real removals.** Songs that failed to delete stay in the library and are no longer counted as removed.
- **Sleep timer checkbox toggles once.** Nested tap handlers no longer cancel each other out, and both modes forward the setting to the player.
- **Details and updater fail safely.** Song details tolerate deleted files and DB errors, and an updater with no ABI report no longer guesses the wrong APK.

## v3.12.2

Design and polish release: existing screens follow the app's Material 3 tokens and interactions settle smoothly, with no new features added.

## Improvements

- **Theme-consistent colors.** Error states, inactive controls and empty-state icons now use `colorScheme` roles, so the UI follows the chosen accent and stays correct in dark and AMOLED themes.
- **Unified bottom sheets.** Sheets inherit the shared 24 dp shape instead of per-screen 20 dp overrides, and the accent check icon switches between black and white for contrast.
- **System bars follow the theme.** Status and navigation bar colors and icon brightness update with the active light, dark or AMOLED theme after the splash hands off.
- **Smoother motion.** A short dismiss drag eases back instead of snapping, the queue scrolls to the playing song, and the playing indicator settles to rest when paused.
- **Labelled controls.** Overflow menus and icon-only actions carry localized tooltips for TalkBack.

## Bug fixes

- **Playlist reorder keeps the displayed order.** Dragging now replaces the source list, so cached rows cannot show the old order or write a wrong order on a second drag.
- **Bulk edit reports success correctly.** A successful database write is no longer reported as a failure when the library reload fails.
- **Clipboard failures are handled.** Copying or pasting a backup shows feedback instead of throwing an unhandled error.
- **Suggestions and the sleep timer behave.** Tapping a search suggestion commits the query, and the sleep timer wheel no longer fights the sheet drag.

## v3.12.1

Optimization release: existing features are lighter, smoother and more native on Android, with no new features added.

## Improvements

- **Large queues stay responsive.** Clearing Up Next removes the tail in one pass instead of one rebuild per song, saving a queue as a playlist uses a single batched insert, and the MediaSession publishes a 40-song window instead of the whole library.
- **Dashboard and duplicate scan load less.** The dashboard reads lightweight song summaries and fetches full rows only for the songs shown in rank tiles, and the duplicate count sends compact fields to its isolate instead of every song with lyrics.
- **Native navigation everywhere.** Subpages now use standard Material routes with the shared Android transition instead of iOS-style horizontal slides. Touch targets meet 48 dp and the splash bars match the navy background.
- **Album covers resolve once.** The cover song per album is chosen when grouping is rebuilt, not again for every visible card on every frame.

## Bug fixes

- **Deleting the playing song while paused no longer resumes the old file.** The replacement song's source is loaded at zero before playback can start.
- **Boot-time restore failures surface.** A failed playback restore is shown once instead of being silently treated as already seen.
- **Queue save handles duplicate names before creating.** Playlists are loaded before the name check, so an existing name gets a suffix instead of a failed insert.
- **Corrupt database columns no longer hide songs.** Non-string optional fields resolve to null instead of throwing in `Song.fromMap`.
- **Async failures stay quiet.** Effect-session broadcasts have timeouts, preference writes are guarded, and the update dialog pops only if it is still open.

## v3.12.0

Deep audit and feature release: library data is protected on rescans, playback stays in sync, and new DSP, backup and auto-playlist tools arrive.

## New features

- **Loudness normalization.** A native `LoudnessEnhancer` lifts quiet passages with a gentle +6 dB target; the switch lives in Settings and is applied to each new audio session.
- **Forgotten Favorites auto playlist.** Favorites not played for 90 days (or never played) are collected into a self-updating playlist beside Daily Mix and Unplayed. Auto playlists now carry an explicit flag, so renaming one keeps it automatic.
- **Save backup to a file.** The backup export dialog can write a timestamped JSON file to Downloads, and Settings shows when the last export happened.

## Improvements

- **System text scaling is preserved.** The in-app text scale multiplies the OS accessibility scale instead of replacing it.
- **Lyrics and accessibility polish.** Synced lyrics follow the audible player after a crossfade, lyric timing controls and accent swatches have 48 dp touch targets, and the A-Z rail supports TalkBack stepping.
- **Android hardening.** The media browser service and media button receiver require `MEDIA_CONTENT_CONTROL`, minSdk matches the documented Android 8.0, and lockscreen transport actions include play, pause and stop.

## Bug fixes

- **Moved files keep their library data.** A rescan no longer deletes a re-pathed row or lets a MediaStore re-id replace it with a fresh row, so favorites, playlists and history survive folder moves and storage migrations.
- **Sleep timer cannot fight a crossfade.** The fade aborts any in-flight crossfade, clears pending A-B loops, and never advances the track after playback stops.
- **Dead sessions recover.** Unplayable files skip to the next song instead of stalling the queue, deleted songs leave the live queue, and a failed playback restore rolls back instead of showing a phantom mini player.
- **Seek and notification state stay honest.** Slider drags no longer flood native seeks or fight A-B repeat, skip buttons clamp to the real duration, and seeking while paused updates the notification position.

## v3.11.0

Rebrand release: Swara is the bamboo panpipe mark everywhere, from the launcher to the splash screen.

## Improvements

- **New app icon.** Dark bamboo-panel tile with gradient yellow-to-green panpipes, shown on the launcher (round and square), in the notification shade, on the home-screen widget, and in the splash screen. All icon densities regenerated, and `ic_stat_swara.xml` is a mono silhouette for notifications.
- **Identity-consistent native splash and widget.** The Android 12+ splash screen, the home-screen widget art, and the launcher foreground now share the panpipe glyph and the dark bamboo panel, so cold start and widget art match the app icon in spirit.
- **Themed and round icons.** The adaptive icon now carries a monochrome layer for Android 13+ themed icons, and the round icon variant is registered in the manifest. The widget picker preview shows the widget art, and the in-app splash positions the mark exactly where the native splash shows it.

## v3.10.0

Another deep-audit round plus new features: song detail sheet, skip ±10 s buttons, verified-update cancel, backup completeness report.

## New features

- **Song details sheet.** Long-press any song > Details to see artist, album, genre, format, duration, file size, file path and play count. The sheet's path is selectable text so it can be copied for support tickets.
- **Skip 10 seconds on the Now Playing screen.** Two new buttons flank the skip-previous/skip-next controls and seek 10 s in either direction.

## Improvements

- **Backup tells you what it couldn't restore.** Songs missing from this library no longer vanish silently: playlist members, favorites and history rows skipped because their source songs are gone are counted and shown next to the success message.
- **Backup restores correctly into a fresh install.** Playlist ordering is preserved via the export's createdAt, and an existing folder assignment is never overwritten (only a missing one is filled).
- **Verified updater stops a stalled download.** The update dialog now has a Cancel button that aborts the download anytime; the download stream also has a 30-second timeout per chunk.
- **Data-management snackbars use a generic localized message** instead of raw exception text.

## Bug fixes

- **Widget elapsed card did not show the restored position.** The cold-restore push now uses the saved position so the widget never shows 0:00.
- **Seek skipped the widget re-push.** Position discontinuities re-push the widget base; the chronometer stays honest after slider seeks and A-B loops.
- **Freshly restored playlists were reordered.** Now the export's createdAt is honored on import.

## v3.9.0

A deep-audit hardening pass and polish release on top of v3.8.0.

## Improvements

- **Home widget shows the elapsed time.** The widget displays the position and, while playing, ticks by itself every second without the app pushing updates; after a cold restore it shows the saved position instead of 0:00.
- **A verified, resilient updater.** The updater checks the SHA-256 digest GitHub publishes for the APK, installs silently on match, and asks for explicit consent otherwise; unverified or mismatched downloads are discarded before the installer opens. v3.9.0 also adds an x86_64 build for emulators and Chromebooks.
- **Backup is complete and self-describing.** The export now round-trips playlist folders, restored history reports how many rows were skipped because their songs are gone, and the restore UI uses dedicated messages instead of raw error text.

## Bug fixes

- **Widget elapsed time drifted after seeking.** The widget position now re-pushes whenever the position stream jumps discontinuously (A-B loops, slider seeks, restores), so the chronometer does not drift far from the playhead after a seek.
- **Chronometer format was rejected.** `%m:%s` is not a legal Android Chronometer format; the widget now uses the documented `%s` value form, which compiles.
- **Import could silently lose history without a word.** Skipped rows are now counted and surfaced next to the success message (playlist folder restoration included).
- **Digest mismatch reported as a generic failure.** The updater now shows a distinct message when the downloaded APK does not match the publisher build, and the raw error text is no longer shown to users.

## CI

- **Every push runs analyze and tests before the APK builds**; the 3-ABI matrix (`arm`, `arm64`, `x86_64`) is the centerpiece of `build.yml` and `build-apk.yml`.

## v3.8.0

Polish release on top of v3.7.0: a self-measuring home widget, a fully verified updater, and the rest of the deep-audit fixes.

## Improvements

- **Home-screen widget shows the elapsed time.** The widget displays the position and, while playing, ticks by itself every second without the app updating it; after a cold restore it shows the saved position instead of 0:00.
- **Installing an unverified update now asks.** The updater only installs the APK silently when the publisher digest matches; otherwise the app asks for explicit confirmation before the installer opens.
- **Playlist folders survive a backup.** Export now carries each playlist's folder, and import restores it, so exporting and importing a backup no longer flattens your playlist organization.
- **Anything left from the audit.** The noisy receiver now opts into scoped broadcasting on Android 13+, media session art is evicted in halves, and the widget state is re-pushed immediately after the art cache is cleared.

## Bug fixes

- **Cold-restore widget showed 0:00.** The widget now uses the restored position before the player re-emits a position event, so the elapsed-time display is correct right after launch.
- **Update verification loop blocked the app.** Hashing the APK for SHA-256 ran on the main thread; it now runs on a background thread, and the Material You theme cache follows palette changes instead of freezing to the initial wallpaper colors.
- **Widget art and on-update decodes ran on the main thread.** Both now run on a background executor, and a widget tap arriving while the app exits no longer throws.

## v3.7.0

Big update: a native home-screen widget with album art, Material You colors, an updater that verifies what it downloads, and a deep audit that fixed every confirmed anomaly across playback, backup, database and the widget.

## Improvements

- **Home-screen widget with album art.** The widget now shows the current album cover next to the title and artist, decoded on a background thread without touching the main looper, with a navy placeholder when no art exists.
- **Material You.** A new toggle in Settings → Appearance makes Swara follow the Android 12+ system accent colors; off keeps the seeded palette, and unsupported Android falls back silently.
- **Same artwork in notification, widget and splash.** All surfaces now use the same azure wave glyph and navy tile.

## Bug fixes

- **Track changes no longer corrupt the queue after crossfade.** Removing, reordering or shuffling the queue while a crossfade is in flight now cancels the fade first; previously the fade could land on the wrong song.
- **Slider and play/pause icon survive crossfades.** The three player streams are now re-keyed on the audible player instance, so they no longer freeze on the outgoing track.
- **Update downloads are verified.** The updater checks the SHA-256 digest GitHub publishes for the APK asset and refuses to install a mismatch; truncated downloads are rejected before the installer ever sees them.
- **Widget taps are never swallowed.** Taps before Flutter's handler is armed are buffered natively and replayed instead of dropping; shortcut and widget cold starts both wait for the playback restore.
- **Backup restore no longer doubles history.** Listening-history dedup now happens inside the insert transaction, and the playlist-member check is chunked so large backups import fully.
- **Half-applied database upgrades cannot commit.** Schema migrations now check column existence with `PRAGMA table_info` before `ALTER TABLE`.
- **No more stuck progress dialog.** The download progress dialog closes and disposes even when the settings screen is gone mid-download.
- **MediaSession queue no longer republishes on every notify.** Drag-reorder storms coalesce into one republish 200 ms after the queue settles.
- **System effect broadcasts are deduplicated.** Wavelet-class apps no longer get repeated OPEN notifications for the same play state.
- **Art cache eviction is incremental.** The notification art cache evicts its oldest half instead of clearing everything.
- **Widget strings now follow the system locale.** Indonesian translators included for all widget strings.

## v3.6.3

A proper intro: the splash screen now choreographs the mark, wordmark and loader, and hands off to the app with a soft fade.

## Improvements

- **Smoother intro animation.** Cold start now fades the mark in while it scales up from 0.88, staggers the "Swara" wordmark right behind it, and shows a small animated equalizer instead of a spinner while the app loads; the status bar and background match the native splash, and the handoff to the app is a soft fade. Reduced motion settings get opacity-only with the loader replaced by a static bar.

## v3.6.2

The icon was redrawn: the letterform is gone, the sound wave is back as one continuous gesture flowing into a play arrowhead.

## Improvements

- **New app icon.** Swara is now a single azure sound wave on a deep navy tile that flows into a play arrowhead drawn with the same stroke, no glow, no gradients. Same mark in the notification icon, the widget and the splash screen.

## v3.6.1

Hotfix: the queue screen showed a blank grey page in v3.6.0.

## Bug fixes

- **Queue screen opened to a blank grey screen.** The queue used a scoped listener without the provider it needs being registered for it, so the screen crashed on build. PlayerService is now registered in the app's provider tree, and the queue screen provides it locally like every other screen. A widget smoke test plus a source guard prevent this regression.

## v3.6.0

New brand icon plus a native-feel polish pass: Android 12+ splash screen, a smaller release build and a deep performance audit.

## Improvements

- **New app icon.** Swara is now a geometric lowercase "s" with an azure sound-drop accent on a deep navy tile. The mark is crisper at small sizes, and the notification and widget use the same mono glyph.
- **Native splash screen on Android 12 and later.** Cold start shows the navy tile and the brand glyph instead of a white flash; older Android keeps a simple navy splash.
- **Smaller install.** Release builds now use R8 minification and resource shrinking, and native libraries load directly from the APK instead of being extracted, reducing both APK and install size.
- **Playlist, queue and search screens rebuild less.** Playlist rows and the mini player only rebuild when their own song or play state changes; the queue rebuilds only when the queue or current track changes; search rebuilds only when the library actually changes.
- **Backup import and iTunes cache replay run off the main thread.** A large restore no longer blocks the UI, and bulk scans replay cached metadata without stalling.
- **Duplicate detection runs off the main isolate.** The Collections screen shows the duplicate count when it is ready instead of computing it during startup.

## Bug fixes

- **Restore did hundreds of queries per row.** Favorites and listening history imported from a backup are now checked with chunked batched lookups; large restores apply in seconds instead of blocking.

## v3.5.3

Fix release: the equalizer button now always does something, and the queue screen opens instantly even on very large libraries.

## Bug fixes

- **Queue screen froze and triggered "not responding".** With shuffle off, opening the queue forced every row above the playing one to build in a single frame to compute its scroll offset. Rows now have a fixed height the list can compute from, so jumping to the playing row is instant at any queue size.
- **"Open system equalizer" did nothing.** When no system equalizer app (Wavelet or the phone's built-in panel) was installed, or no audio session existed yet, the button returned silently. It now always falls back to an in-app equalizer sheet with presets and the 5-band custom editor.

## Improvements

- **Shared equalizer controls.** The preset chips, custom band sliders and band visualizer now live in one widget used by both Settings and the in-app equalizer sheet, so the two never drift apart.
- **Clearer equalizer copy.** The system equalizer row now says it falls back to the in-app one, and the fallback sheet explains why it is showing.

## v3.5.2

Hardening release for the in-app updater and the home screen widget, plus a few cold-start edge cases.

## Bug fixes

- **Installer always opened the wrong screen.** Fresh installations could never install an update in place because the system blocked unknown sources silently and the app showed success anyway. The updater now checks the `Install unknown apps` permission, opens the right Android settings screen when it is missing, and only reports success after the system installer actually runs.
- **Widget taps were unreliable on strict ROMs.** The widget receiver path could be blocked by Android's background activity restrictions. Widget buttons now launch the activity directly with the action as an intent extra, replayed by Flutter on cold start and delivered to the live engine on warm start.

## Improvements

- **Widget updates only on state changes.** Slider drags during playback no longer rebuild the widget many times per second; it only rebinds when the song or play state actually changes.
- **Cold restore guard is set before the seek.** A restored near-end track can no longer fire crossfade, A-B repeat or auto-advance on its own before the user presses play.
- **Corrupt preferences can no longer kill the library.** A failing SharedPreferences read now falls back to title A-Z instead of aborting the whole database load.
- **A fresh sort tap wins.** Tapping a sort option immediately after startup can no longer be reverted by the late stored-value read.
- **Installer fallback.** When the system installer cannot start for any reason, the user is taken to the GitHub releases page instead of seeing a dead-end error.

## v3.5.1

Bug-fix release: audit passes that stamp out anomalies across the player, the scanner, the updater and the library.

## Bug fixes

- **Crossfade never advanced the queue.** The position watchdog cut the track before the fade landed, so `next()` aborted the fade and restarted from zero; the watchdog now yields while a fade owns the track, and the pause path stops the blended pair.
- **Bulk scans persisted nothing.** Titles, artists, art and lyrics refetched by bulk and missing-art/missing-lyrics flows were dropped on the next reload; they now persist.
- **Cold restore froze all automation.** A restored track never auto-advanced, faded, or A-B looped until the user touched the screen; the cold-start guard now lifts on any playback action.
- **Resume shifted playback.** Deleting or moving one song shifted the restored queue by one; resume now anchors to the song id.
- **Moved files lost history.** Songs renamed or relocated were ghosted and wiped along with playlists, favorites and listening history; moved files are matched by name and duration and keep their rows.
- **Installer always failed.** The update install intent lacked `FLAG_ACTIVITY_NEW_TASK`; the system installer now opens and can finish the install.
- **Queue showed stale data.** Rename/favorite edits never reached the queue snapshot; the library now pushes fresh fields into matching queued rows.
- **Startup sort could be ignored.** The stored sort order now applies deterministically from the first load.

## Improvements

- **DB upgrade to v10.** The Indonesian "Tidak diketahui" placeholder is replaced with the language-neutral "Unknown" for genre and region.
- **Updater picks the right APK.** The in-app updater selects the arm64, armeabi-v7a or x86_64 split that matches the device.

## v3.5.0

Up-front permissions, an in-app update path from the About screen, support links for the developer, and smaller quality-of-life defaults.

## New features

- **Permissions up front.** Fresh installs now ask for music access and notification permission at first launch, instead of during onboarding or the first scan.
- **In-app updates.** Tapping the version row in About checks the latest GitHub release and, when one exists, downloads the right split APK for your device and installs it in place. No uninstall needed.
- **Support section.** About now offers direct donation links: GitHub Sponsors, Saweria, SociaBuzz, and BagiBagi.
- **Player setup persists.** Shuffle and repeat choices survive a restart; previously only crossfade, speed, pitch, and smart shuffle did.

## Improvements

- **Text scale tightened up.** Small is a bit smaller than default, Normal stays the 0.85 default, Large is the top option, and extra-large is gone.
- **Follow system by default.** Fresh installs follow the system appearance; dark is no longer the forced default.

## Bug fixes

- **Duplicate finder shows itself.** The duplicate finder card in Collections only appears when there are duplicates to find; it no longer shows an empty promise.

## v3.4.0

A native-experience release: playback state resumes where you left off, a real system equalizer, a home screen widget, and crossfade that never skips songs.

## New features

- **Playback resume.** The app reopens paused at the last song and minute:second you listened, like a native player.
- **Home screen widget.** Swara shows the current song with previous, play and next controls right on the home screen.
- **Headset unplug pause.** Playback pauses automatically when the headset is unplugged or the Bluetooth route is lost.
- **System equalizer shortcut.** A new row in Settings opens Wavelet or the phone's built-in equalizer for the current session, the same standard panel flow.
- **Embedded cover art.** Cover art stored inside the audio file is extracted and shown automatically, no network fetch needed.

## Improvements

- **The in-app equalizer is real DSP now.** The presets and the custom 5-band curve are applied through the system audio effect on the active session; the old plugin never returned a result, so the sliders changed nothing.

## Bug fixes

- **Crossfade broke auto advance.** With crossfade enabled, songs stopped continuing automatically after a few tracks because reused players could stop emitting the completed event; a position watchdog now guarantees the queue moves forward.
- **Player screen froze on the old song.** Starting a new song could leave the player showing the previous title; the screen now rebuilds per song id.

## v3.3.0

A performance release: lists and artwork now render like a native player, and the project follows one shared release process.

## New features

- **Native-smooth lists.** Library, search, and dashboard lists now decode artwork at display size, skip per-frame layout work, and repaint only what changed, so scrolling stays fluid on large libraries.

## Improvements

- **Release body comes from the changelogs.** The release generated by the build workflow now lists the changelog instead of hardcoded notes, and the release title is `Swara vX.Y.Z`.
- **Android project committed.** The `android/` folder is now part of the repository instead of being regenerated and patched by CI on every build, so builds are reproducible and the workflows are shorter.

## Bug fixes

- **Wrong author avatar.** The Author section in the READMEs now links the real author avatar and profile.

## v3.2.0

One shared theme for the whole app, artwork that flies from the mini player into the player, and one calm page transition everywhere.

## New features

- **One design system.** A new `lib/theme/app_theme.dart` defines the app bar, cards, dialogs, list rows, buttons, snackbars, tabs, dividers, bottom sheets and page transitions in one place; light and dark are both built by the same function, so the two can no longer drift apart.
- **Artwork flies into the player.** Tapping the mini player grows its small cover into the big cover on the player screen, instead of swapping two unrelated pictures.
- **One page transition everywhere.** Screens open with a short fade and a small upward slide rather than the default zoom, and the player keeps its own motion from the bottom.

## Improvements

- **Muted text follows the theme.** Seventy hardcoded grey text and icon colors across fifteen files now use the theme's secondary color, so they adapt to light, dark and AMOLED backgrounds and to the accent color you pick.
- **Floating snackbars.** Snackbars no longer hug the bottom edge just because a screen forgot to ask for floating behavior.
- **Library tabs match the app.** Selected and unselected labels, and the hairline under the bar, now come from the theme instead of Material defaults.
- **Progress bars follow your accent.** The loading track used to stay the default purple when your accent was teal or orange; it now uses your theme.

## Bug fixes

- **One muted grey.** Three different greys for the same kind of text are gone; they now all use one themed color, especially readable on the AMOLED black background.
- **One shape.** Dialogs, sheets and rows keep one shape; hand-styled corners per screen meant the same kind of popup looked different depending on where it opened.

## v3.1.0

Metadata scans now start only when you start them, and you can stop any scan without losing work already fetched.

## New features

- **Manual metadata scans.** Metadata scans never start on their own; the app used to kick off a background enrich a few seconds after startup, quietly spending your data and the iTunes rate limit on songs you were not looking at, and a scan now runs only when you start it yourself from the library menu, Settings, or a folder screen.
- **Stoppable scans.** Every scan can be stopped, with a stop control wherever a scan is running: the library header, the Settings tile, the missing covers screen, the missing lyrics screen, and the folder screen; the batch already in flight finishes and everything fetched so far is kept, so stopping never wastes the work done before it.
- **Stop feedback.** When a scan ends early because you stopped it, the app says the scan was stopped and that everything fetched was kept, instead of reporting the whole job as finished.

## Improvements

- **Lighter startup.** The automatic background enrich that ran five seconds after opening the app is gone, so launching Swara no longer starts network requests on its own; music still appears instantly from the local database, and the local file scan that keeps newly added songs visible is unchanged.
- **Verification.** 201 tests pass, including new guards that fail if a screen starts a metadata scan on its own or if a stop control is removed; flutter analyze reports no issues; the English and Indonesian READMEs were updated to describe the manual behavior.

## Bug fixes

- **Real folder scan progress.** The folder scan progress bar now tracks the real job; it was measured against every song in the folder even when only the unscanned ones were being processed, so it could stall short of full, and it now uses the actual target count.

## v3.0.0

A major hardening release with no new screens: safer to install, lighter on old dependencies, and covered by a clean security audit.

## Improvements

- **Backups disabled.** Your local library can no longer be pulled off the phone with adb; the Android manifest allowed backups by default, which meant anyone with physical access and USB debugging could extract the whole SQLite database (your library, favorites, and full listening history) with one command, and backups are now disabled including cloud backup and device to device transfer, because Swara has no account and nothing worth exporting.
- **Clean security audit.** A full security audit of the codebase came back clean where it mattered; the Git history across 133 commits contains no leaked API keys or tokens, every external call (iTunes, lrclib, lyrics.ovh) already uses HTTPS and never plain HTTP, and all database access uses parameterized queries instead of string concatenation, so no SQL injection path exists, with the listening history, playlists and metadata cache all checked.
- **Self-printing hardening.** The build now prints its own hardening, and the CI pipeline echoes the hardened manifest on every run, so a regression shows up in the build log instead of shipping silently.
- **Dependencies updated.** Six dependencies were brought up to date within their safe ranges, including the database layer (sqflite 2.4.5), the file picker, preferences storage, and the cache manager, the libraries that run on every scan and every screen load.
- **R8 left off deliberately.** R8 full minification is deliberately not enabled; the Flutter obfuscation flag only covers Dart code, and turning on full minification would let R8 strip native classes that plugins such as on_audio_query reach through reflection and JNI, crashing on a real device and nowhere else, so the APK stays lean through obfuscation and per-architecture splits instead of risking the size saved.
- **Verification.** 196 tests pass, unchanged after the dependency updates; flutter analyze reports no issues; the hardened manifest is printed in every CI run.

## Bug fixes

- **No functional changes.** The scan and lyrics fixes from v2.9.10 through v2.9.13 are all included in this build.

## v2.9.13

Synced and plain lyrics now come from a single lrclib lookup, in one request.

## New features

- **Single lrclib lookup.** Synced lyrics and plain lyrics now come from one lrclib request, since lrclib returns both forms in a single response, instead of two separate requests against two different services.
- **Synced-only lyrics show text.** When a source provides only the timed form, the app strips the timestamps to build the plain view, so the lyrics panel is never left empty.
- **Cached songs included.** An lrclib lookup now completes the synced view for songs already in the cache, so older entries are not stuck without scrolling lyrics.

## Improvements

- **Half the lyrics requests.** One network request replaces two per song, because lrclib alone now serves both forms, which halves the requests during a metadata scan.
- **Lyrics off main thread.** All lyrics HTTP now runs off the main thread; the lrclib lookup moved into a background isolate like the lyrics.ovh one, so a scan or a lyrics fetch no longer stalls the interface, and the shared main-thread HTTP client is gone because every request now owns its client inside its isolate.
- **Verification.** 196 tests pass, including new guards that pin the single request and the fallback order; flutter analyze reports no issues.

## Bug fixes

- **Atomic lyrics storage.** A failed lyrics lookup no longer leaves the song half done, because the plain and the synced paths now share one capped storage helper, so a payload can never be written uncapped and a cache write failure no longer disturbs a fetch that already succeeded.
- **lyrics.ovh as fallback.** lyrics.ovh stays as a fallback only and is consulted when lrclib has no entry for a track, which keeps songs that lrclib is missing working instead of leaving them without lyrics.

## v2.9.12

Scan fixed after a type mismatch made it fail for every single song.

## Improvements

- **Verification.** 191 tests pass, including new guards for the isolate type mismatch; flutter analyze reports no issues.

## Bug fixes

- **Scanning works again.** The off-thread scanner handed its work to a background isolate, and one of the values sent across that boundary was a set of excluded folders that was read back as a list; the type mismatch threw before a single song was looked at, so the library stayed empty even with permission granted and music on the phone, and the value is now coerced instead of cast while the sender passes an unambiguous plain list.
- **Isolated value failures.** A bad value can no longer take a whole scan down with it, because the scanner degrades an unexpected excluded-folders value to an empty set, so a mismatch can cost you the folder filter rather than every song.
- **Guard test added.** A guard test now pins this exact failure by checking for the cast that broke the scan, so it cannot quietly come back.

## v2.9.11

The "Open Settings" shortcut now appears reliably when music access is denied, as a focused follow-up to v2.9.10 with correctness changes only.

## Improvements

- **Verification.** 188 tests pass, including the corrupt-row guards that keep one bad song from blanking the library; flutter analyze reports no issues.

## Bug fixes

- **Reliable Open Settings.** The "Open Settings" button on the "No music yet" screen now actually appears when music access is denied; it used to be decided by matching text inside an error message, which could silently fail to match, and the app now tracks the denial explicitly so the shortcut shows up reliably.
- **Dual permission check.** A denied permission is now checked on both the audio and legacy storage permission, which older devices that fall back to storage rely on; they previously reported the wrong state, so the shortcut never appeared there.
- **Crash-proof permission check.** The permission check can no longer crash the scan because it is wrapped in its own guard, so a failure there degrades to a plain error message instead of losing the scan result entirely.

## v2.9.10

Music detection fixed so the library no longer stays empty after storage access is granted, with correctness and diagnostics changes only.

## Improvements

- **Verification.** 188 tests pass, including new guards that pin the corrupt-row handling; flutter analyze reports no issues.

## Bug fixes

- **Blank library fixed.** A song whose file path was empty (which MediaStore can report on scoped storage) used to throw while loading and hide every other song at once; the loaders now skip that one row instead of dropping the whole library.
- **Empty paths filtered.** The scanner used to insert songs with an empty file path straight into the database, which triggered the blank-library bug; they are now filtered out during the off-thread scan.
- **Self-explaining scan failures.** The "No music yet" screen previously hid the reason a scan found nothing; it now shows the error, and when music access was permanently denied it offers a button straight to the app settings.

## v2.9.9

A permanent lint gate and stricter async context guards, with no change to what you see or hear.

## Improvements

- **Permanent analyzer gate.** The project now enables flutter_lints plus prefer_single_quotes and sort_child_properties_last through a new analysis_options.yaml, so style and correctness issues surface before they ship on every change.
- **Verification.** 185 tests pass and flutter analyze reports no issues, now enforced by a committed analysis_options.yaml.

## Bug fixes

- **Mounted guards added.** Fourteen use-after-await context sites now carry a proper mounted guard, so snackbars, dialogs, and navigation after an async gap check that the widget is still alive, removing a class of latent crashes when a screen closes while work is still running.
- **Lint findings resolved.** Forty-two lint findings across the codebase are resolved, mostly const constructors, single quotes, renamed shadowed locals, and hoisted comments; none of them change runtime behavior.

## v2.9.8

A pure weight-reduction release with no new features and no behavior changes, trimming work while scrolling and searching.

## Improvements

- **Search normalization caching.** Search normalization now runs once per row and once per query, and the typo-tolerant pass no longer rebuilds its regular expressions or re-normalizes the query for every song, which halves the work per keystroke.
- **Cached playlist view.** The playlist detail screen sorts and filters once, not once per rebuild, with its sorted view and total duration cached per source list, sort mode and query, so keyboard, favorite and playback updates no longer re-sort the whole playlist.
- **Code-unit sort comparison.** Sorting compares code units instead of regular expressions, and the title sort tier check used a regex per comparison but now reads the first character's ASCII range directly.
- **Cached filtered lists.** Favorites and the missing art or lyrics lists are cached per library version, so those screens no longer rebuild their filtered list on every scan progress notification.
- **Throttled art cache touch.** The cover art cache updates file timestamps at most once every 10 minutes per cover, instead of firing one filesystem call per tile just to keep the cache order fresh.
- **Hoisted scan regexes.** Scanned filename parsing and duplicate grouping hoist their regular expressions, so a full rescan no longer compiles patterns once per file.
- **Verification.** 185 tests pass, including new guards that pin the hoisted regexes, the cached playlist view and favorites list, and the throttled art cache touch; flutter analyze reports no issues.

## Bug fixes

- **No behavior changes.** Every optimization in this release is internal; search results, sorting order, favorites, and the missing art or lyrics lists all behave exactly as before.

## v2.9.7

A pure weight-reduction release with no new features, trimming search, sorting, and row updates.

## Improvements

- **Isolate search matching.** Fuzzy matching and the typo pass moved to a background isolate, so they no longer run on the frame where you type, and their per-song text is built once per library version instead of on every keystroke.
- **Single-row updates.** Favoriting, renaming, and refreshing metadata for one song now patch that row in memory instead of re-querying, re-sorting, and rebuilding every consumer.
- **Index-based player lookup.** The player screen looks up the playing song by index instead of scanning the entire library on every playback notification.
- **One-time sort keys.** Sort keys are computed once per song, so sorting no longer lowercases both sides inside every comparison, which used to allocate hundreds of thousands of strings per load.
- **Verification.** 178 tests pass, including new guards that pin the isolate search path, the in-memory row patches, and the index lookup; flutter analyze reports no issues.

## Bug fixes

- **Favorites stay in sync.** Favorite changes now bump the library version the favorites list is gated on, keeping the favorites screen in sync with the lighter in-memory updates.

## v2.9.6

Faster scans and a per-song metadata refresh.

## New features

- **Refresh one song.** The song menu now has a "Scan metadata" action that fetches title, album art, genre, and lyrics for just that single song without touching the rest of the library.

## Improvements

- **Off-thread scanning.** Folder checks, title fallbacks, and write batching now run in a background isolate, so the UI stays responsive while thousands of songs are scanned.
- **Off-thread lookups.** iTunes and lyrics lookups no longer run on the main thread, so metadata fetching no longer blocks frames during a bulk scan.
- **Lighter startup.** The background metadata pass starts 5 seconds after the first frame instead of running inline.
- **Verification.** 169 tests pass and flutter analyze reports no issues.

## Bug fixes

- **Build error fixed.** A missing `mounted` guard broke the CI build.
- **Captive portal restored.** Only answers that actually look like iTunes or lyrics.ovh are stored as a "not found" miss, while HTML pages, 5xx responses, and other surprises stay retryable instead of locking a song out for 90 days.
- **Isolate hidden-folder parity.** Hidden folder exclusion behaves exactly as before inside the new isolate path, including Windows style paths.
- **Line-ending agnostic tests.** The source inspection guards no longer depend on line endings, so they pass on Windows checkouts too.

## v2.9.5

Lighter scrolling for large libraries and smaller default text.

## Improvements

- **Smoother library scroll.** The scroll listener no longer calls `setState` on every fling, so scrolling the large library no longer freezes or blocks gesture handling on lists with thousands of songs.
- **Smaller default text.** The app opens with a default text scale of 0.85 so more rows fit on screen without scrolling.
- **Memory-only cover lookups.** The cover index is built once at startup, so scrolling no longer touches the disk per frame.
- **Verification.** 169 tests pass and flutter analyze reports no issues.

## v2.9.4

A stability release: database reads no longer crash on corrupt rows.

## Bug fixes

- **Corrupt data casts.** Casts of `as int` without guards on corrupt database data crashed in seven sites; they are now guarded so corrupt rows are skipped instead of crashing.

## v2.9.3

A security fixes release: security audit findings are fixed, including URL injection, content-type validation, and path traversal.

## Improvements

- **Audit fixes.** URL injection is blocked, downloaded covers are checked against their content type, and path traversal in backup restore is rejected.

## v2.9.2

Fixes listening streaks breaking on DST transition nights, captive portals locking songs as not found, and the dashboard ignoring hidden folders.

## Improvements

- **Verification.** 169 tests pass and flutter analyze reports no issues.

## Bug fixes

- **DST streak fixed.** The streak calculation used 24-hour subtraction, which could land at 23:00 on daylight saving time change nights and cut the streak one day early.
- **Captive portal 404s.** A captive portal (hotel, airport, campus WiFi) can return a 404 with an HTML body for an iTunes URL, which used to be treated as a definitive "song not found on iTunes" result and lock every affected song's metadata as unavailable for 90 days; now only responses that actually look like iTunes are committed as misses.
- **Dashboard hidden folders.** Songs from hidden folders were still counted in the dashboard totals, were listed in "never played", and "play all" would start hidden songs; the dashboard now respects hidden folders.

## v2.9.1

A stability release: startup crash, settings not saving, and songs missing after a scan are fixed.

## Bug fixes

- **Startup crash.** Fixed a crash on startup.
- **Settings saving.** Settings now save correctly.
- **Missing songs.** Songs missing after a scan are now detected.

## v2.9.0

Search that forgives typos, so small slips still find the right track.

## New features

- **Typo-tolerant search.** Search now tolerates swapped letters and single mistakes, so "fadde" or "wlaeker" find "Faded" and "Walker", with exact matches always first so a near miss can never push the song you actually typed down the list.
- **Spelling hint when empty.** If a query returns nothing and a close word exists, the empty state offers that word as a one-tap suggestion.

## Improvements

- **Exact short words.** Words of four letters or fewer match exactly, because allowing one edit there would match most of the dictionary.
- **Edit budget by length.** Five and six letter words allow one edit, and seven letters or more allow two.
- **Transposed letters count once.** Swapped letters count as a single edit, while plain Levenshtein counts them as two and would force a tolerance so loose the search becomes useless.
- **Two-edit ceiling.** Beyond two edits nothing is guessed, since a wrong suggestion is worse than no suggestion and a wrong result is worse than no result.
- **Verification.** 169 tests pass, including a dedicated suite for the edit distance, the tolerance rules and the suggestion logic.

## v2.8.0

This release brings lyric timing, a smoother equalizer, and a calmer dashboard.

## New features

- **Lyric timing control.** Sync lyrics now read the standard offset tag from .lrc files, which many tracks ship with, and two buttons let you nudge the lyrics by 100 ms in either direction; the correction resets when the song changes, because a timing tuned to one track means nothing on the next.

## Bug fixes

- **Long lyrics scroll.** Long lyrics now scroll to the active line: the highlight could move while the visible text stayed frozen, more often the longer the lyric was, because rows outside the viewport were never built.
- **Stable EQ slider.** The equalizer slider no longer fights itself: dragging a band fired dozens of competing writes and a preview repaint per pixel, so the curve could settle on a blend of values instead of the one you chose.
- **Honest EQ status.** The equalizer tells you whether it works: Settings now shows EQ active or EQ unavailable on this device instead of pretending.
- **Shuffle remembers.** Smart shuffle remembers what you have not played in a while: after every app restart that half of the ranking was dead, so everything looked equally stale.
- **Reliable notification.** The notification cannot freeze permanently: a stop request from Android or a headset used to detach the handler for the rest of the session, after which the title, position and shuffle buttons stopped moving.
- **Accurate dashboard counts.** Dashboard counts now match what you see: songs from folders you hid were still counted, listed and playable, so the dashboard could claim more songs than the library showed.
- **Move playlist feedback.** Moving a playlist to a folder can no longer fail silently: a failed move used to close the dialog with no message at all.
- **Settings always saved.** Settings are always saved: two quick taps could leave the stored value disagreeing with the screen until the next restart.

## Improvements

- **Threaded playlist covers.** Playlist covers are built off the main thread: composing one decoded four full resolution images on the UI isolate froze the app for seconds, and the old cache only compared the song count, so a swapped song kept a stale cover.
- **Memory-only covers.** Cover art lookups are memory only, indexed once at startup.
- **Atomic collage writes.** Playlist collage writes are atomic, so a kill mid write can no longer leave a half written cover that looks valid.
- **139 tests.** 139 tests include new coverage for lyric offset parsing, equalizer serialization, handler teardown, collage fingerprinting and dashboard folder filtering.

## v2.7.1

Crossfade and equalizer finally work in this release.

## Bug fixes

- **Crossfade transitions.** Crossfade no longer breaks every transition: the finished track raised its normal completion event in the middle of its own fade, which started the next song, cancelled the fade and restarted the incoming track from its first second, so you heard a jump instead of a smooth transition; the completion handler now steps aside while a fade is running.
- **Working equalizer.** The equalizer now actually changes the sound: the audio plugin never replies to its own commands, so every preset and slider change timed out and no gain ever reached the output; commands are now sent without waiting, readiness is confirmed with a call that does reply, and band levels are sent in dB instead of being scaled twice, which asked your phone for +40 dB, outside the allowed range.
- **No second voice.** Repeat one no longer leaves a second voice behind: with a crossfade involved, the other player kept playing the fading track faintly in the background.
- **Accurate duplicate finder.** The duplicate finder no longer deletes a different recording: a studio track and a live version of the same song were treated as duplicates, and removing all duplicates deleted the live version along with its playlist entries and history; album and duration now take part in matching, and every delete is checked.
- **Live Daily Mix.** Daily Mix and Unplayed follow your changes: hiding a folder or rescanning now updates them, instead of keeping hidden songs until the app was restarted.
- **Hidden folders respected.** Most Played respects hidden folders: songs from a folder you hid could still be listed and played there.
- **Sticky A-B loop.** Setting an A-B loop during a crossfade now sticks instead of being dropped a moment later.
- **No disk while scrolling.** Album art no longer touches the disk while scrolling, because cover lookup happened on every rebuild of every row.

## Improvements

- **Batched bulk edit.** Bulk edit is one batch instead of one reload per song: editing 500 songs used to reload the whole library 500 times and froze the app.
- **Memory-only covers.** Cover art lookups are memory only, with a single index built at startup.
- **127 tests.** 127 tests include new regression checks that cover the crossfade race, the equalizer units, duplicate matching, bulk edit batching and hidden folder handling.

## v2.7.0

This release stops scans from wiping your metadata.

## Bug fixes

- **Metadata preserved.** Rescans no longer erase enriched metadata: every device scan wrote each known song as a brand new row built from the file tags alone, and SQLite REPLACE deletes the old row before inserting, so every pull to refresh and every automatic scan on startup blanked out album covers, genres, regions and lyrics and undid manual metadata edits; existing songs now only receive the facts that actually come from the file, such as its path and duration.
- **No scan race.** Overlapping scans can no longer delete freshly added songs: two scans running at the same time compared the song table against their own device snapshot, so the slower one removed the songs the faster one had just inserted along with their playlist entries and listening history; a second scan is now ignored while one is running, and the cleanup compares against a snapshot taken before the scan started.
- **Fetch actually saves.** Fetch from the internet now actually saves: in Edit Metadata the button filled the form with fresh values but wrote nothing to the database, so closing the screen lost everything and the snackbar still said success; it now stores the result, reaches the network instead of replaying a cache entry up to 30 days old, and says so plainly when the request was skipped because of rate limiting.
- **History taps work.** Tapping a row in History no longer fails silently: playing a song whose file disappeared threw an uncaught error, so the tap did nothing with no message.
- **Fresh dashboard numbers.** Cleaning listening history now refreshes the dashboard numbers, because the summary cards were cached for 10 minutes while the detail lists were always fresh, so one screen could show two different versions of the same statistic.

## Improvements

- **Lighter notifications.** The notification no longer rebuilds its whole queue on every state change: the media session allocated one item per queued song before even checking whether the queue had changed, which was wasteful during a volume drag or a speed change.
- **Honest rescan.** A deliberate rescan is honest about rate limiting instead of reporting success when nothing was fetched.
- **119 tests.** 119 tests include a new regression suite that blocks the metadata wiping, the scan race and the rescan that does not persist from coming back.

## v2.6.2

This release delivers smoother playlist writes and safer M3U import.

## Bug fixes

- **Correct M3U matching.** M3U import no longer adds the wrong song: when an entry only matched by file name and several songs shared that name, the app picked the first one at random, and an ambiguous name is now reported as unmatched instead of guessed.
- **Fade-in song kept.** Clear up next keeps the song that is currently fading in, because pressing it during a crossfade could delete the incoming track while it was still audible.
- **Accurate header duration.** The library duration in the header is always correct, as it is now summed once per load and adjusted when songs are deleted.

## Improvements

- **One-transaction adds.** Adding many songs to a playlist is now one transaction instead of re-reading the whole playlist and the row position for every single song, which made a merge, a bulk add or an M3U import quadratic and large selections noticeably slow.
- **Single library update.** Removing duplicates updates the library once instead of rebuilding the row index and the A-Z map for every deleted row.
- **One-query backup restore.** Restoring a backup checks song ids with one query and inserts the members in one transaction, instead of one round trip per playlist member.
- **Cheaper header sums.** The header no longer re-sums every duration on each rebuild, which was the main source of stutter during a metadata scan.
- **114 tests.** 114 tests include new coverage for M3U path matching and for the ambiguous file name case, so the wrong song cannot come back silently.

## v2.6.1

This release delivers audit fixes for v2.6.0.

## Bug fixes

- **Listening history safe.** v2.6.0 pruned rows older than 12 months automatically during the database upgrade, and because dashboard totals are computed from that history with no date filter, Total listened, Top songs, Top artists and the listening hours chart could silently shrink; cleanup is now an action you trigger yourself in Settings, and the dialog says plainly that those numbers will go down.
- **Pragmas actually apply.** WAL and the other pragmas were being set from inside the migration transaction, where SQLite refuses to change journal mode and the failures were swallowed; they now run before the transaction and the result is verified.
- **No startup stall.** The prune ran inside the migration transaction despite a comment saying it was fire and forget, which delayed the database open.
- **Correct date comparison.** History cleanup compares dates correctly, so entries restored from a backup with a timezone offset are no longer at risk.
- **Indexes match sort.** Artist and album indexes used a different collation than the queries, so SQLite ignored them and every sort stayed a full scan; indexes are also retried on every open, so a failed index now heals itself.
- **Fresh jump index.** A-Z jump and search results can no longer go stale when metadata changes without changing the song count, for example after a metadata scan.
- **Reliable sleep schedule.** A leftover flag could stop playback after the first song, and the sheet did not update when a scheduled session started while it was open.
- **Speed remembered.** Speed and pitch are remembered across restarts, and dragging the slider no longer rebuilds the whole player screen on every frame.
- **Safe select all.** Select all is capped, bulk writes are batched, and the result message now reports what really happened instead of the requested count.
- **No row overflow.** List rows no longer overflow when the text size setting is increased.
- **Stable search results.** Search results no longer rebuild entirely on every play or pause, and grouping work is cached instead of repeated on each scan progress update.

## Improvements

- **Localization parity enforced.** Localization parity is now enforced by tests: every English key must exist in Indonesian with the same placeholders.
- **Prune regression test.** A regression test blocks the automatic history prune from coming back.

## v2.6.0

This release brings full lists, speed control, and smart shuffle.

## New features

- **Full lists.** Every list now shows all items at once with no Load more button, while scrolling stays smooth on huge libraries.
- **Instant A-Z jump.** A-Z jump is instant via an in-memory letter index, and shuffle or play always covers every song.
- **Jump to playing.** The jump-to-playing-song button appears when the current track is off screen.
- **Select all rows.** You can select all rows directly from the multi-select bar.
- **Speed and pitch.** Playback speed runs from 0.5x to 2.0x with pitch control, live apply and reset, all from a chip in the player.
- **Smart shuffle.** A smart shuffle favors rarely played and long unplayed songs.
- **Daily sleep schedule.** A daily sleep schedule starts a 30 minute sleep timer by itself at your chosen time.
- **Play all buttons.** Play all and Shuffle buttons now appear on the Albums, Artists, and Genres screens.

## Improvements

- **Faster database.** The database now runs in SQLite WAL mode with tuned pragmas, memory mapped reads, and new indexes on artist, album, title, and play timestamp.
- **History pruning.** Listening history is pruned automatically (12 months, with a row cap) so the database stays small.
- **Lazy search.** Search now renders results lazily with a 250 ms debounce and a stale-result guard instead of paging.
- **Smaller thumbnails.** Cover thumbnails are decoded at a small size in every list, which cuts memory and jank.

## Bug fixes

- **Browser links work.** Search lyrics on Google (and the developer link) now open the browser again, since the app could not see any browser on Android 11 or newer without a package visibility declaration and no longer relies on a canLaunch check that always failed there.

## v2.5.0

Merge playlists, build a custom equalizer, and switch to a pitch-black AMOLED theme.

## New features

- **Merge playlists.** Merge one playlist into another, skipping duplicates.
- **Missing lyrics.** A missing-lyrics list with batch refetch.
- **Adjustable crossfade.** The crossfade duration is adjustable from 0 to 12 seconds.
- **Custom equalizer.** A custom 5-band equalizer.
- **AMOLED theme.** An AMOLED pitch-black theme option.
- **Shortcuts and text size.** Launcher shortcuts and a text-size setting are available.

## v2.4.1

A fix for the silent pause-resume, audible equalizer presets, and honest credits.

## Bug fixes

- **Resume silence.** Pause then resume no longer goes silent; resume no longer dips through zero volume, and failed play calls now report an error and retry.
- **Audible presets.** The equalizer now scales levels to real millibels, so presets are actually audible.
- **Whole-library shuffle.** Shuffle and play in All Songs now cover the whole library, not just rendered rows, and the A-Z jump loads pages as needed.
- **Honest credits.** About now shows the real app version plus a proper developer credit with logo.

## v2.4.0

A-B loops for practice and quick actions from the app icon.

## New features

- **A-B repeat.** Loop any segment of a song for practice.
- **Bulk edit.** Change genre and artist across many songs at once.
- **Launcher shortcuts.** Shuffle favorites and continue listening straight from the app icon.
- **Text size setting.** Adjust text size from small to extra large.

## Improvements

- **Smoother artwork.** Artwork renders more smoothly with flicker-free image updates.

## v2.3.2

A more reliable equalizer and the official logo.

## New features

- **Official logo.** Official Swara launcher icons and a splash logo.

## Improvements

- **Smoother UI.** Selective list rebuilds and an isolated countdown keep the UI smooth.

## Bug fixes

- **Equalizer lock-ups.** Equalizer preset changes can no longer lock up; plugin calls now time out instead of hanging.
- **Resume silence.** Pause then resume no longer goes silent because volume operations are serialized.
- **Queue accuracy.** The notification queue stays correct with duplicate songs and reorders.

## v2.3.1

A deep round of stability fixes across rescans, timers, lyrics, and startup.

## Bug fixes

- **Safer rescans.** Library rescans no longer wipe enriched metadata and manual edits.
- **Sleep timer.** The sleep timer now works with crossfade on, and repeat-one stays consistent.
- **Rapid taps.** Rapid tapping can no longer play a different song than the one shown.
- **Lyrics retry.** Offline lyrics failures are retried instead of ignored for 90 days.
- **Accessible controls.** The repeat button is a proper accessible button, and the mini player and sort chips have touch ripples.
- **Faster startup.** Startup is no longer blocked by the notification permission dialog.

## v2.2.0

A real, audible equalizer and a new set of library tools.

## New features

- **Real equalizer.** A working equalizer with 9 presets shaping actual playback sound, no longer visual-only.
- **Duplicate finder.** Find duplicate songs and clean them up in bulk.
- **Missing covers.** A missing-covers list with batch refetch.
- **Playlist folders.** Organize playlists into folders.
- **Forgiving search.** Search tolerates small mistakes, so "faded alan walker" finds "faded - alan walker".

## v2.1.0

Share your yearly recap as an image and enjoy a smarter, more reliable queue.

## New features

- **Shareable recap.** Share the yearly recap card as an image.
- **Queue as playlist.** Save the play queue as a playlist in one tap.
- **Bedtime schedule.** A sleep timer locked to a fixed clock time every night.
- **Extended multi-select.** Multi-select is now extended to search results and favorites.
- **Album sorting.** Albums can now be sorted.
- **Real queue controls.** The notification and lockscreen now use the real playback queue with proper next/previous.

## v2.0.0

Everything since v1.6 in one milestone: an English-first bilingual app, smart playlists, synced lyrics, backup and restore, yearly recap, and a much lighter, faster build.

## New features

- **English-first UI.** The English interface is now the default, with Bahasa Indonesia in Settings (390+ localized strings).
- **Smart auto-playlists.** Daily Mix and Unplayed are generated automatically.
- **Synced lyrics.** LRC lyrics sync to playback with follow-along highlighting.
- **Sleep timer.** A sleep timer with gentle fade-out.
- **Backup and restore.** Backup and restore your data via JSON.
- **Onboarding.** A first-launch onboarding flow.
- **Yearly recap.** Yearly recap, listening streaks, and the top genre of the month.
- **Import and sharing.** M3U import, song sharing, and playlist cover collages.

## Improvements

- **Under the hood.** Per-architecture APKs, SQL-paged lists, lazy players, deferred metadata fetching with caching, gzip lyrics, and zero `flutter analyze` issues with 75 passing tests.

## v1.9.1

This release brings M3U import, sharing, and streaks.

## New features

- **M3U import.** Import playlists from .m3u/.m3u8 files, matched against your library.
- **Song sharing.** Share songs (info plus audio file) from the song menu.
- **Listening streaks.** The dashboard shows your listening day streak and top genre of the month, with cached aggregates.
- **Faster cold start.** Parallel initialization behind a splash screen makes cold starts faster.

## Improvements

- **Disk-cached remote art.** Remote album art is cached on disk (100MB LRU) instead of re-downloaded every launch.
- **On-demand playlists.** Playlist data loads on demand, and an unused icon font was removed.

## v1.9.0

This release brings smarter playlists and synced lyrics.

## New features

- **Smart auto-playlists.** Smart auto-playlists Daily Mix (25 fresh songs every day, reshufflable) and Unplayed are maintained automatically.
- **Synced lyrics.** Synced (LRC) lyrics highlight along with the song and auto-scroll, plus a plain view toggle.
- **Fading sleep timer.** The sleep timer fades volume out instead of stopping abruptly.
- **Backup and restore.** Export and import playlists, favorites, and history as JSON, plus album-art cache size info and cleanup.
- **First-launch onboarding.** The app now has first-launch onboarding.
- **Clear notification toggles.** Notification shuffle/repeat buttons now show clearly whether they are on or off.
- **Polished UI.** Consistent padding, loading skeletons, centered empty states, and 48px touch targets polish the UI.

## Improvements

- **Longer lyrics caching.** Lyrics fetch results are cached longer, and synced lyrics are stored locally.

## v1.8.3

This release makes the app use less data and less memory.

## New features

- **On-demand playlists.** Playlist data now loads on demand instead of at startup.

## Improvements

- **Lyrics negative cache.** Missing lyrics are remembered (90-day negative cache) instead of re-fetched every time you open a song.
- **Shared HTTP client.** One shared HTTP client handles all metadata traffic (fewer repeated connections).
- **Display-sized album art.** Album art is decoded at display size (thumbnails for tiles, full size only on the player).

## v1.8.2

This release makes the install slimmer and kinder to your battery.

## New features

- **Phone-only builds.** Only phone architectures are published now (arm64 + armv7), with no more emulator-only build in the downloads.
- **First widget test.** The first widget test landed among 67 total tests.

## Improvements

- **Disk-cached metadata.** Metadata responses are cached on disk (30 days, misses 90 days) so reinstalls skip re-fetching everything.
- **Compressed lyrics.** Lyrics are stored gzip-compressed in the database.
- **Sleeping position stream.** The position stream sleeps while paused, and notification sync does less redundant work.
- **Built-in image widgets.** The heavy image-caching dependency was dropped in favor of built-in image widgets.

## v1.8.1

This release brings lighter downloads and a faster startup.

## New features

- **Per-architecture APKs.** Download the small build matching your phone instead of one universal APK.
- **Paged long lists.** Long lists (All Songs, Search) render in pages of 200 with a Load more button.
- **First unit tests.** The first unit tests add 46 tests covering filename parsing and formatting helpers.

## Improvements

- **Much smaller downloads.** Downloads are much smaller now via split-per-ABI, obfuscation, trimmed resources, and narrowed R8 keep rules.
- **Faster first paint.** The song list appears right after the first frame; heavy metadata fetching is deferred and backs off on rate limits.
- **Lazy second player.** The second audio player is now created lazily only while crossfade is enabled.
- **Leaner notification sync.** Notification sync skips redundant work every second, and the play indicator animation stops when paused.

## Bug fixes

- **Honest CI build.** The CI build step no longer swallows real failures.

## v1.8.0

This release makes English the default language of the app, with Bahasa Indonesia one tap away in Settings.

## New features

- **English by default.** The app UI is now English by default; switch to Bahasa Indonesia anytime in Settings, remembered between sessions.
- **New Language section.** A new Language section in Settings offers English and Bahasa Indonesia options.

## Improvements

- **ARB localization files.** All ~390 user-facing strings moved to ARB localization files (a single source of truth, no more hardcoded text scattered across screens).
- **English code comments.** Code comments were translated to English across the codebase.

## Bug fixes

- **Localized messages.** Validation, error, and confirmation messages now follow the selected language, including provider-level errors.
- **intl bumped.** intl was bumped to match flutter_localizations requirements.

## v1.7.0

This release is a deep clean-up under the hood, fixing player leaks, optimizing database queries, and making bulk actions instant.

## New features

- **Bulk favorite.** Select many songs and favorite them all in one action.
- **Dashboard error state.** The dashboard shows an error state with retry instead of loading forever when the database fails.
- **Live sleep-timer label.** The sleep-timer label updates live for song-count mode.

## Improvements

- **Single-JOIN most-played query.** The most-played query is now a single JOIN instead of loading the whole library into memory, with new database indexes for sorting and dashboard queries.
- **Single-query folders.** The folder screen loads with one query and groups in memory (it was one full table scan per folder).
- **Debounced search.** Search input is debounced and results are computed once per build.
- **Parallel dashboard loading.** The dashboard loads all statistics in parallel.
- **Lyrics respect manual edits.** Lyrics auto-fetch no longer overwrites your manual title/artist/album edits.
- **Flutter 3.47 migration.** The codebase migrated to Flutter 3.47 APIs (RadioGroup, onReorderItem, withValues).
- **Clean analysis.** The app is verified with zero `flutter analyze` issues.

## Bug fixes

- **Audio player leaks fixed.** Audio player and stream-subscription leaks are fixed (proper dispose, no more stuck play/pause icon after crossfade).
- **Queue race fixed.** The queue race when adding songs to an empty queue is fixed.
- **Crossfade mix-up fixed.** Repeat/shuffle/speed no longer act on the wrong internal player during crossfade.
- **Crash fixes.** Crashes from empty titles/artists, corrupt database rows, and missing art files in notifications are fixed.
- **EQ text fixed.** The misleading EQ text is fixed (it is a visual preset, it does not change actual sound).
- **Dead notification service removed.** The dead notification service that referenced a dropped dependency is removed.

## v1.6.0

This release brings configurable library tabs and redesigned collections.

## New features

- **Configurable library tabs.** The "Musik" page is now **Perpustakaan**, with configurable tabs: **Songs, Albums, Artists, Folders, Genres** (toggle and drag-to-reorder via the settings sheet).
- **New Albums tab.** The new **Albums** tab shows a 2-column cover-art grid.
- **Collections redesigned.** Collections now show 4 colorful quick-access cards (**Favorites, Recently Added, Recently Played, Most Played**) above the playlist list.
- **New Search page.** The new **Search** page (magnifier icon in the AppBar) offers filters: **Songs, Albums, Artists, Folders, Genres**.
- **Collapsible headers.** Collapsible headers everywhere slide the Play + Shuffle buttons away on scroll.
- **Finger-following A-Z popup.** The A-Z popup on the scrollbar follows your finger, with a fade-out animation.
- **Rebuilt sleep timer.** The sleep timer was rebuilt with an iOS-style drum picker (hours/minutes or song count), a big countdown, and stop and close buttons.
- **Multi-select songs.** Long-press to multi-select songs and favorite or add them to a playlist in bulk.
- **10 accent colors.** 10 custom accent colors are available and saved between sessions.
- **EQ presets.** EQ presets (Flat, Pop, Rock, Classical, Jazz, Electronic, Hip-Hop, Bass Boost, Vocal) come with an animated visualizer.
- **Dashboard revamp.** The dashboard no longer duplicates Collections: 7-day activity chart, Top 5 songs + artists, genre distribution, unplayed songs.

## Improvements

- **One-time scan.** Music appears instantly from the local database; the device scan only runs when needed or after 30 minutes.

## v1.4.0

Background playback now uses a real Android foreground service with MediaSession, so notification controls and the lockscreen finally work properly.

## New features

- **Foreground service playback.** Music controls now use a real Android foreground service with MediaSession: notification controls and lockscreen (play/pause/next/previous) finally work properly, replacing the old plain-icon notification that could let music die in the background.
- **Live sleep timer label.** The sleep-timer countdown now shows directly on the player page (minutes:seconds or songs remaining).

## Bug fixes

- **Now playing indicator.** The "now playing" indicator on All Songs updates instantly on track change; previously only after leaving and returning to the page.
- **Indicator everywhere.** Folders, Playlists, and Favorites now show the "now playing" indicator; previously none did.
- **No confirmation toast.** Removed the sleep-timer confirmation notification that covered player controls.
- **Cleaner player.** Removed the "Tap cover to see lyrics" hint for a cleaner player.

## v1.3.0

This release is a deep stability pass: safer scans that never wipe your library by surprise, a working custom sleep timer, and crossfade-aware repeat.

## Improvements

- **Sorting everywhere.** A-Z, Z-A, Artist, and Date Added sorting are now available on Folders, Favorites, and Playlists.
- **A-Z on collections.** A-Z scrollbar navigation is now available on Folders and Favorites.
- **Sort memory.** The sort choice is remembered per page.
- **Manual scans only.** Metadata scan no longer runs automatically on launch, only on demand.
- **Smoother motion.** Smoother transitions and item animations across all pages.
- **Scan safety guard.** Scans never wipe the library if MediaStore suddenly returns empty (for example after a reboot or a fresh permission grant).
- **Stable titles.** Long song titles no longer flicker on incoming notifications.

## Bug fixes

- **Custom sleep timer.** The custom sleep timer (hours and minutes) can now actually be set.
- **Sleep timer stops.** The sleep timer really stops the music; previously it paused the wrong player.
- **Repeat with crossfade.** Repeat-one now works while crossfade is active.
- **Folder prefix match.** `/storage/Music` no longer shows songs from `/storage/Music2` and similarly named folders.
- **Folder refresh.** Folder metadata refreshes right after scan, with no need to leave the folder.
- **Playlist reorder.** Playlist drag-reorder no longer flashes moved items.
- **Empty search results.** Play and Shuffle buttons disable on empty search results, preventing RangeError crashes.
- **Truly random shuffle.** Shuffle always starts from a truly random song.
- **Background notification.** The music-control notification is more responsive in the background.
- **Favorite on save.** Favorite status no longer resets when saving metadata edits.
- **Memory leak.** Fixed a memory leak on the edit-metadata page and hidden errors when navigating to closed pages.

## v1.2.1

The favorite toggle finally toggles and crossfade runs continuously between songs instead of only on the first transition.

## Bug fixes

- **Favorite toggle.** The Favorite button in the three-dot menu now truly toggles; previously it always added, so songs could never be unfavorited from there.
- **Continuous crossfade.** Crossfade now runs continuously between songs; previously only the first transition worked.
- **Dashboard crash.** Fixed the dashboard crash when rendering the 7-day chart.
- **Shuffle always on.** Shuffle always enables; previously it could turn shuffle off if already on.
- **Date added.** "Date added" sort now uses the actual library-add time.
- **Cached album art.** Album art is now cached locally instead of being re-fetched every time.
- **Batched metadata scan.** Bulk metadata scan runs in batches: faster and friendlier to free APIs.
- **Unusual paths.** Fixed a potential crash when scanning files with unusual paths.

## v1.2.0

A-to-Z quick navigation and a manageable play queue make big libraries fast to browse.

## New features

- **A-Z jump.** Full A-to-Z quick navigation, jumping to the nearest available letter.
- **Play queue.** Manageable play queue: drag to reorder, swipe left to remove.
- **Per-song menu everywhere.** The full per-song menu (play next, playlist, rename, edit, delete) is now also on Folders and Favorites.
- **Play and shuffle buttons.** Play and Shuffle buttons on Folders, Playlists, and Favorites, not just All Songs.
- **Lyrics view.** Tap lyrics to return to the cover view; the edit-lyrics button is always visible.
- **Marquee titles.** Long song titles auto-scroll neatly on the player page.
- **True folder hiding.** Hidden folders are now truly absent from All Songs.

## Bug fixes

- **Mini player.** The mini player now appears immediately when music starts, from any page.
- **Notification controls.** Music-control notification now has the correct permission and icon buttons.

Note: the music-control notification is still being refined and may be unstable on some devices.

## v1.1.0

Gestures, a sleep timer, and themes: this release turns the player into a full-screen experience you can drive with impossible-to-miss gestures.

## New features

- **Swipe gestures.** Swipe down on the player to minimize; swipe left/right for next/previous song.
- **Lyrics on tap.** Tap the album cover to see lyrics instantly; Google lyrics search when auto-fetch finds nothing.
- **Sleep timer and speed.** Sleep timer with custom duration; playback speed control from 0.5x to 2x.
- **Search and sort.** Real-time song search; sorting A-Z/Z-A/genre/date.
- **Folders and rescan.** Hide folders from the library; rescan metadata per song or all at once.
- **Settings and theme.** Settings page with light/dark theme; smooth animations throughout.

## Bug fixes

- **First play.** The player now appears on first play; previously it needed playing twice.

## v1.0.0

The first release of the offline music player for Android, built with Flutter: scan your collection and the app completes titles, artists, album art, genres and even lyrics over the internet, with all listening data staying on-device and available offline.

## New features

- **Offline playback.** Scan and play music straight from phone storage.
- **Auto metadata.** Titles, artists, album art, genres and lyrics are fetched over the internet on demand.
- **Dashboard.** Last-7-days listening hours, most-played songs and artists, genre and region distribution.
- **Library basics.** Browse by source folder; custom playlists, favorites, and recently played.
- **Playback controls.** Shuffle, repeat (off/all/one), and a sleep timer; manual metadata editing.
