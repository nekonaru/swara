// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsFollowSystem => 'Follow system';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsDark => 'Dark';

  @override
  String get settingsAccentColor => 'Accent color';

  @override
  String get settingsAccentPurple => 'Purple';

  @override
  String get settingsAccentBlue => 'Blue';

  @override
  String get settingsAccentTeal => 'Teal';

  @override
  String get settingsAccentGreen => 'Green';

  @override
  String get settingsAccentOrange => 'Orange';

  @override
  String get settingsAccentRed => 'Red';

  @override
  String get settingsAccentDeepPurple => 'Deep purple';

  @override
  String get settingsAccentPink => 'Pink';

  @override
  String get settingsAccentCyan => 'Cyan';

  @override
  String get settingsAccentLightGreen => 'Light green';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsCrossfade => 'Crossfade';

  @override
  String get settingsCrossfadeSubtitle =>
      'Seamless transition between songs (3 seconds)';

  @override
  String get settingsEqualizer => 'Equalizer';

  @override
  String get settingsEqualizerNote =>
      'These presets shape the actual playback sound through the system equalizer. Your choice is saved between sessions.';

  @override
  String get settingsLibrary => 'Library';

  @override
  String get settingsScanFiles => 'Scan music files';

  @override
  String get settingsScanFilesSubtitle =>
      'Check for new or removed music files on this device (offline)';

  @override
  String get settingsScanMissing => 'Scan missing metadata';

  @override
  String get settingsScanMissingSubtitle =>
      'Fetch title/artist/cover from the internet for new songs';

  @override
  String settingsScanProgress(int progress, int total) {
    return 'Processing $progress/$total...';
  }

  @override
  String get settingsRescanAll => 'Rescan all metadata';

  @override
  String get settingsRescanAllSubtitle =>
      'Fetch again from the internet for ALL songs';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsAboutVersion(String version) {
    return 'v$version';
  }

  @override
  String get settingsDeveloper => 'Developer';

  @override
  String get settingsDeveloperName => 'Nicolas Dwi Dharma';

  @override
  String get settingsRescanTitle => 'Rescan all';

  @override
  String settingsRescanMessage(int count) {
    return 'Fetch metadata again for all $count songs from the internet? This takes longer.';
  }

  @override
  String get settingsRescanStart => 'Start';

  @override
  String get languageSection => 'Language';

  @override
  String get languageSubtitle => 'Application language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Remove';

  @override
  String get add => 'Add';

  @override
  String get create => 'Create';

  @override
  String get search => 'Search';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Something went wrong';

  @override
  String get empty => 'Nothing here yet';

  @override
  String get confirm => 'Confirm';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get unknown => 'Unknown';

  @override
  String get failed => 'Failed';

  @override
  String get corePlayFailed => 'Could not play';

  @override
  String get coreScanFailed => 'Scan failed';

  @override
  String get coreUpdateFavoritesFailed => 'Could not update favorites';

  @override
  String get coreSongAlreadyInPlaylist =>
      'This song is already in the playlist';

  @override
  String get coreRemoveFromPlaylistFailed =>
      'Could not remove the song from the playlist';

  @override
  String get coreSavePlaylistOrderFailed => 'Could not save the playlist order';

  @override
  String get corePermissionDenied => 'Music access permission was denied';

  @override
  String get coreSongs => 'songs';

  @override
  String playlistLoadFailed(String error) {
    return 'Failed to load playlist: $error';
  }

  @override
  String playlistReorderFailed(String error) {
    return 'Failed to save order: $error';
  }

  @override
  String playlistRemoveFailed(String error) {
    return 'Failed to remove song: $error';
  }

  @override
  String get playlistSortCustom => 'Custom order';

  @override
  String get playlistSortTitleAZ => 'Title A-Z';

  @override
  String get playlistSortTitleZA => 'Title Z-A';

  @override
  String get playlistSortArtistAZ => 'Artist A-Z';

  @override
  String get playlistEmpty => 'This playlist is still empty';

  @override
  String playlistSummary(int count, String duration) {
    return '$count songs - $duration';
  }

  @override
  String get playlistSearchHint => 'Search in this playlist...';

  @override
  String get playlistPlay => 'Play';

  @override
  String get playlistShuffle => 'Shuffle';

  @override
  String get playlistReorderHint => 'Press and drag to reorder';

  @override
  String get playlistNoResults => 'No songs found';

  @override
  String historyLoadFailed(String error) {
    return 'Failed to load history: $error';
  }

  @override
  String get historyEmpty => 'No playback history yet';

  @override
  String get dashboardLoadFailedTitle => 'Failed to load dashboard';

  @override
  String get dashboardRetry => 'Try Again';

  @override
  String get dashboardEmptyTitle => 'Empty dashboard';

  @override
  String get dashboardEmptySubtitle =>
      'Listening stats will appear after you start playing songs.';

  @override
  String get dashboardTotalSongsLibrary => 'Total songs in library';

  @override
  String get dashboardTotalSongs => 'Total songs';

  @override
  String get dashboardTotalListened => 'Total listened';

  @override
  String get dashboardThisMonth => 'This month';

  @override
  String dashboardHoursValue(String hours) {
    return '$hours hours';
  }

  @override
  String get dashboardListeningWeekTitle =>
      'Listening Hours in the Last 7 Days';

  @override
  String dashboardWeekTotal(String hours) {
    return '$hours hours total';
  }

  @override
  String get dashboardTopSongs => 'Top 5 Songs';

  @override
  String dashboardUnknownSong(int id) {
    return 'Song #$id';
  }

  @override
  String dashboardPlayCount(int count) {
    return '${count}x played';
  }

  @override
  String dashboardPlayFailed(String error) {
    return 'Failed to play song: $error';
  }

  @override
  String get dashboardTopArtists => 'Top 5 Artists';

  @override
  String get dashboardGenreTitle => 'Genre Distribution';

  @override
  String dashboardGenreCount(int count) {
    return '$count genres';
  }

  @override
  String get dashboardNeverPlayedTitle => 'Never Played';

  @override
  String dashboardSongCount(int count) {
    return '$count songs';
  }

  @override
  String dashboardNeverPlayedSubtitle(int count) {
    return '$count songs in your library have never been played.';
  }

  @override
  String get dashboardPlayAll => 'Play All';

  @override
  String get dashboardWeekActivityTitle => 'This Week Activity';

  @override
  String get dashboardNoWeekActivity => 'No activity this week yet.';

  @override
  String dashboardActiveDays(int count) {
    return '$count of 7 days actively listening';
  }

  @override
  String dashboardNeverPlayedSheetTitle(int count) {
    return '$count songs never played';
  }

  @override
  String get dashboardDaySun => 'Sun';

  @override
  String get dashboardDayMon => 'Mon';

  @override
  String get dashboardDayTue => 'Tue';

  @override
  String get dashboardDayWed => 'Wed';

  @override
  String get dashboardDayThu => 'Thu';

  @override
  String get dashboardDayFri => 'Fri';

  @override
  String get dashboardDaySat => 'Sat';

  @override
  String dashboardTooltipMinutes(int mins) {
    return '${mins}m';
  }

  @override
  String dashboardTooltipHours(String hours) {
    return '${hours}h';
  }

  @override
  String get editMetadataValidationEmpty =>
      'Title, artist, and album cannot be empty';

  @override
  String editMetadataSaveFailed(String error) {
    return 'Failed to save: $error';
  }

  @override
  String get editMetadataRescanTitle => 'Rescan from the Internet?';

  @override
  String get editMetadataRescanMessage =>
      'Data from the internet will overwrite your manual edits in this form. Continue?';

  @override
  String get editMetadataRescanConfirm => 'Yes, Overwrite';

  @override
  String editMetadataRescanFailed(String error) {
    return 'Failed to rescan: $error';
  }

  @override
  String get editMetadataRescanSuccess => 'Metadata updated from the internet';

  @override
  String get editMetadataTitle => 'Edit Metadata';

  @override
  String get editMetadataFetching => 'Fetching data...';

  @override
  String get editMetadataRescanButton => 'Rescan from the Internet';

  @override
  String get editMetadataFieldTitle => 'Title';

  @override
  String get editMetadataFieldArtist => 'Artist';

  @override
  String get editMetadataFieldAlbum => 'Album';

  @override
  String get editMetadataFieldGenre => 'Genre';

  @override
  String get editMetadataFieldRegion => 'Region Origin';

  @override
  String get editMetadataEditLyricsButton => 'Edit Lyrics (separate page)';

  @override
  String get editMetadataSaveButton => 'Save Changes';

  @override
  String get editLyricsClipboardEmpty => 'Clipboard is empty, no text to paste';

  @override
  String get editLyricsPasteTitle => 'Paste Lyrics';

  @override
  String get editLyricsPasteMessage =>
      'There are already lyrics here. Overwrite them (start over) or append to the existing lyrics?';

  @override
  String get editLyricsAppend => 'Append';

  @override
  String get editLyricsOverwrite => 'Overwrite';

  @override
  String editLyricsSaveFailed(String error) {
    return 'Failed to save lyrics: $error';
  }

  @override
  String get editLyricsTruncated =>
      'Lyrics exceeded 100KB and were trimmed when saved';

  @override
  String editLyricsTitle(String title) {
    return 'Edit Lyrics: $title';
  }

  @override
  String get editLyricsPasteButton => 'Paste';

  @override
  String get editLyricsSearchWeb => 'Search on Web';

  @override
  String get editLyricsHint =>
      'No lyrics yet. Paste from clipboard, search the web, or type manually here.';

  @override
  String get editLyricsSaveButton => 'Save Lyrics';

  @override
  String get songOptionsPlayNext => 'Play Next';

  @override
  String get songOptionsAddedPlayNext => 'Added to play next';

  @override
  String get songOptionsAddToQueueEnd => 'Add to End of Queue';

  @override
  String get songOptionsAddedToQueue => 'Added to queue';

  @override
  String get songOptionsAddFavorite => 'Add to Favorites';

  @override
  String get songOptionsRemoveFavorite => 'Remove from Favorites';

  @override
  String songOptionsFavoriteFailed(String error) {
    return 'Failed to update favorite: $error';
  }

  @override
  String get songOptionsAddToPlaylist => 'Add to Playlist';

  @override
  String get songOptionsRename => 'Rename Song';

  @override
  String get songOptionsEditMetadata => 'Edit Metadata';

  @override
  String get songOptionsScanMetadata => 'Scan metadata';

  @override
  String get songOptionsRemoveFromPlaylist => 'Remove from This Playlist';

  @override
  String songOptionsRemoveFromPlaylistFailed(String error) {
    return 'Failed to remove from playlist: $error';
  }

  @override
  String get songOptionsRemovedFromPlaylist =>
      'Removed from this playlist only';

  @override
  String get songOptionsDeleteFromLibrary => 'Delete from Library';

  @override
  String get songOptionsDeleteTitle => 'Delete Song';

  @override
  String songOptionsDeleteConfirm(String title) {
    return 'Delete \"$title\" from All Songs, Folders, Favorites, and Playlists? The original file on your phone is kept - it will appear again if the folder is rescanned.';
  }

  @override
  String songOptionsDeleteFailed(String error) {
    return 'Failed to delete song: $error';
  }

  @override
  String songOptionsRenameFailed(String error) {
    return 'Failed to rename: $error';
  }

  @override
  String get songOptionsCreatePlaylist => 'Create New Playlist';

  @override
  String get songOptionsPlaylistNameTitle => 'Playlist Name';

  @override
  String songOptionsAddToPlaylistFailed(String error) {
    return 'Failed to add to playlist: $error';
  }

  @override
  String songOptionsPlaylistCreated(String name) {
    return 'Playlist \"$name\" created and song added';
  }

  @override
  String songOptionsPlaylistExists(String name) {
    return 'Playlist \"$name\" already exists, pick it from the list';
  }

  @override
  String songOptionsCreatePlaylistFailed(String error) {
    return 'Failed to create playlist: $error';
  }

  @override
  String get librarySortBy => 'Sort by';

  @override
  String get librarySortTitleAsc => 'Title ↑';

  @override
  String get librarySortTitleDesc => 'Title ↓';

  @override
  String get librarySortArtistAsc => 'Artist ↑';

  @override
  String get librarySortArtistDesc => 'Artist ↓';

  @override
  String get librarySortAlbumAsc => 'Album ↑';

  @override
  String get librarySortAlbumDesc => 'Album ↓';

  @override
  String get librarySortDateNewest => 'Date ↑';

  @override
  String get librarySortDateOldest => 'Date ↓';

  @override
  String get librarySortGenre => 'Genre ↑';

  @override
  String get libraryCreatePlaylistFirst =>
      'Create a playlist first in the Collections tab';

  @override
  String get libraryChoosePlaylist => 'Choose playlist';

  @override
  String libraryAddedToPlaylist(int count, String name) {
    return '$count songs added to $name';
  }

  @override
  String librarySelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get libraryAddToPlaylist => 'Add to playlist';

  @override
  String get libraryAddToFavorites => 'Add to favorites';

  @override
  String librarySongCount(int count) {
    return '$count songs';
  }

  @override
  String librarySongCountDuration(int count, String duration) {
    return '$count songs · $duration';
  }

  @override
  String get libraryScanMetadata => 'Scan metadata';

  @override
  String get libraryStartPlaying => 'Start playing';

  @override
  String get libraryShuffle => 'Shuffle';

  @override
  String get libraryScanningMusic => 'Scanning music...';

  @override
  String get libraryNoMusic => 'No music yet';

  @override
  String get libraryScanMusic => 'Scan Music';

  @override
  String get libraryOpenSettings => 'Open Settings';

  @override
  String get libraryScanMissing => 'Scan missing metadata';

  @override
  String get libraryRescanAll => 'Rescan all';

  @override
  String libraryRescanConfirm(int count) {
    return 'Fetch metadata again for $count songs?';
  }

  @override
  String get libraryStart => 'Start';

  @override
  String libraryPlayFailed(String error) {
    return 'Failed to play song: $error';
  }

  @override
  String get searchHint => 'Search music...';

  @override
  String get searchFilterSong => 'Song';

  @override
  String get searchFilterAlbum => 'Album';

  @override
  String get searchFilterArtist => 'Artist';

  @override
  String get searchFilterFolder => 'Folder';

  @override
  String get searchFilterGenre => 'Genre';

  @override
  String get searchPromptTitle => 'Search your music';

  @override
  String get searchPromptSubtitle => 'Type a title, artist, album, or more';

  @override
  String get searchNoResults => 'No results';

  @override
  String searchNotFound(String query) {
    return '\"$query\" not found';
  }

  @override
  String searchResultCount(int count) {
    return '$count results';
  }

  @override
  String get searchOther => 'Other';

  @override
  String get albumsEmpty => 'No album data yet.';

  @override
  String albumsCount(int count) {
    return '$count albums';
  }

  @override
  String get collectionsNewPlaylist => 'New Playlist';

  @override
  String get collectionsPlaylistNameHint => 'Playlist name';

  @override
  String get collectionsDeletePlaylist => 'Delete Playlist';

  @override
  String collectionsDeleteConfirm(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String collectionsDeletePlaylistConfirm(String name) {
    return 'Delete playlist \"$name\"?';
  }

  @override
  String get collectionsFavorites => 'Favorites';

  @override
  String get collectionsRecentlyAdded => 'Recently added';

  @override
  String get collectionsRecentlyPlayed => 'Recently played';

  @override
  String get collectionsMostPlayed => 'Most played';

  @override
  String get collectionsRecentlyAddedTitle => 'Recently Added';

  @override
  String get collectionsRecentlyPlayedTitle => 'Recently Played';

  @override
  String get collectionsMostPlayedTitle => 'Most Played';

  @override
  String get collectionsSortNameAsc => 'Name ↑';

  @override
  String get collectionsSortNameDesc => 'Name ↓';

  @override
  String collectionsPlaylistCount(int count) {
    return '$count playlists';
  }

  @override
  String collectionsPlaylistCountAlt(int count) {
    return '$count playlists';
  }

  @override
  String get collectionsNoPlaylists => 'No playlists yet';

  @override
  String get collectionsCreatePlaylist => 'Create Playlist';

  @override
  String get collectionsFavoritesEmpty => 'No favorites yet';

  @override
  String get collectionsFavoritesHint =>
      'Tap the heart icon on a song to add it';

  @override
  String get collectionsRecentlyAddedEmpty => 'No songs added yet.';

  @override
  String get collectionsMostPlayedEmpty => 'No playback data yet';

  @override
  String get collectionsMostPlayedHint => 'Play songs to see statistics';

  @override
  String foldersLoadFailed(String error) {
    return 'Failed to load folders: $error';
  }

  @override
  String get foldersShownAgain => 'Folder shown again';

  @override
  String get foldersHidden => 'Folder hidden from library';

  @override
  String get foldersEmpty => 'No music folders detected yet.';

  @override
  String foldersCount(int count) {
    return '$count folders';
  }

  @override
  String get foldersSortNameAsc => 'Name ↑';

  @override
  String get foldersSortNameDesc => 'Name ↓';

  @override
  String get foldersSortCount => 'Song count';

  @override
  String get foldersSortCountShort => 'Count';

  @override
  String get foldersHideHidden => 'Hide hidden folders';

  @override
  String get foldersShowHidden => 'Show hidden folders';

  @override
  String get foldersNoSongs => 'No songs';

  @override
  String get foldersAllScanned =>
      'All songs in this folder have already been scanned';

  @override
  String get foldersScanDone => 'Finished scanning this folder\'s metadata';

  @override
  String get foldersSortTitleAsc => 'Title ↑';

  @override
  String get foldersSortTitleDesc => 'Title ↓';

  @override
  String get foldersSortArtistAsc => 'Artist ↑';

  @override
  String get foldersSortDate => 'Date ↑';

  @override
  String get artistsEmpty => 'No artist data yet.';

  @override
  String artistsCount(int count) {
    return '$count artists';
  }

  @override
  String get genresEmpty => 'No genre data yet.';

  @override
  String genresCount(int count) {
    return '$count genres';
  }

  @override
  String get homeLibrary => 'Library';

  @override
  String get homeCollection => 'Collection';

  @override
  String get homeDashboard => 'Dashboard';

  @override
  String get homeTabSongs => 'Songs';

  @override
  String get homeTabAlbums => 'Albums';

  @override
  String get homeTabArtists => 'Artists';

  @override
  String get homeTabFolders => 'Folders';

  @override
  String get homeTabGenres => 'Genres';

  @override
  String get homeTabSettings => 'Tab settings';

  @override
  String get homeTabReorderHint => 'Drag tabs to reorder';

  @override
  String get homeReset => 'Reset';

  @override
  String get homeApply => 'Apply';

  @override
  String get homeMinOneTab => 'At least 1 tab must be active';

  @override
  String get homeSettings => 'Settings';

  @override
  String homeLoadLibraryFailed(String error) {
    return 'Failed to load library: $error';
  }

  @override
  String get homePressAgainToExit => 'Press again to exit';

  @override
  String get playerPlaybackSpeed => 'Playback speed';

  @override
  String get playerCannotOpenBrowser => 'Cannot open the browser';

  @override
  String get playerSearchOpenFailed => 'Failed to open search';

  @override
  String get playerLyricsFound => 'Lyrics found!';

  @override
  String get playerLyricsNotFoundHint =>
      'Lyrics still not found, try adding them manually';

  @override
  String playerSongsRemaining(int count) {
    return '$count more songs';
  }

  @override
  String get playerEmptyState => 'No song is playing yet';

  @override
  String get playerTapToReturnToCover => 'Tap to return to the cover';

  @override
  String get playerEditLyrics => 'Edit Lyrics';

  @override
  String get playerLyricsNotFound => 'Lyrics not found';

  @override
  String get playerTapHereToReturnToCover => 'Tap here to return to the cover';

  @override
  String get playerSearchOnGoogle => 'Search on Google';

  @override
  String get playerAutoSearch => 'Auto Search';

  @override
  String get playerAddManually => 'Add Manually';

  @override
  String get playerPrevious => 'Previous';

  @override
  String get playerNext => 'Next';

  @override
  String get playerFavorite => 'Favorite';

  @override
  String get playerAddToPlaylist => 'Add to Playlist';

  @override
  String get playerSleepTimer => 'Sleep Timer';

  @override
  String get queueTitle => 'Play Queue';

  @override
  String get queueEmpty => 'Queue is empty';

  @override
  String get queueReorderHint =>
      'Press and hold to reorder - swipe left to remove';

  @override
  String get sleepTitle => 'Sleep timer';

  @override
  String get sleepSetTimeAboveZero => 'Set a time greater than 0';

  @override
  String get sleepRemaining => 'remaining';

  @override
  String get sleepFinishLastSong => 'Finish the last song';

  @override
  String get sleepSongsRemaining => 'songs remaining';

  @override
  String get sleepStop => 'Stop';

  @override
  String get sleepTimeMode => 'Time';

  @override
  String get sleepSongMode => 'Songs';

  @override
  String get sleepStart => 'Start';

  @override
  String get sleepSongUnit => 'songs';

  @override
  String get sleepTimerStopped => 'Sleep timer stopped';

  @override
  String loadMore(int shown, int total) {
    return 'Load more ($shown of $total)';
  }

  @override
  String get sleepFadingOut => 'Fading out...';

  @override
  String get sleepStoppingPlayback => 'Stopping playback';

  @override
  String autoPlaylistError(String error) {
    return 'Failed to update auto playlists: $error';
  }

  @override
  String get autoBadge => 'Auto';

  @override
  String get reshuffleDailyMix => 'Reshuffle Daily Mix';

  @override
  String get reshuffle => 'Reshuffle';

  @override
  String get onboardSkip => 'Skip';

  @override
  String get onboardNext => 'Next';

  @override
  String get onboardGetStarted => 'Get Started';

  @override
  String get onboardTitle1 => 'Welcome to Swara';

  @override
  String get onboardDesc1 =>
      'Your offline music player. Grant audio access so Swara can list the songs already on your device.';

  @override
  String get onboardTitle2 => 'Automatic metadata and lyrics';

  @override
  String get onboardDesc2 =>
      'Swara fills in missing album art, artist info, and lyrics automatically so your library always looks complete.';

  @override
  String get onboardTitle3 => 'Ready to listen';

  @override
  String get onboardDesc3 =>
      'Browse songs, build playlists, and check your listening stats on the dashboard. Tap Get Started to begin.';

  @override
  String get dataSection => 'Data';

  @override
  String get dataExport => 'Export backup';

  @override
  String get dataExportSubtitle =>
      'Copy playlists, favorites, and history as JSON';

  @override
  String get dataImport => 'Import backup';

  @override
  String get dataImportSubtitle => 'Restore from pasted backup JSON';

  @override
  String get dataArtCache => 'Album art cache';

  @override
  String get dataArtCacheMeasuring => 'Measuring cache...';

  @override
  String dataArtCacheUsage(String bytes, int files) {
    return '$bytes in $files files';
  }

  @override
  String get dataRefresh => 'Refresh';

  @override
  String get dataClearArtCache => 'Clear art cache';

  @override
  String get dataClearArtCacheSubtitle =>
      'Delete cover files and clear references';

  @override
  String get dataExportTitle => 'Export backup';

  @override
  String dataExportReady(int chars, String size) {
    return 'Backup ready: $chars characters, $size. Copy it to the clipboard for safekeeping.';
  }

  @override
  String get dataCopy => 'Copy';

  @override
  String get dataCopied => 'Backup copied to clipboard';

  @override
  String dataExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get dataImportTitle => 'Import backup';

  @override
  String get dataImportPrompt =>
      'Paste a backup JSON string, or load it from the clipboard.';

  @override
  String get dataImportHint => 'Paste backup JSON here';

  @override
  String get dataPaste => 'Paste';

  @override
  String get dataImportAction => 'Import';

  @override
  String get dataConfirmImportTitle => 'Confirm import';

  @override
  String get dataConfirmImportMessage =>
      'Import will add missing playlists, favorites, and history entries. Continue?';

  @override
  String dataImportDone(
      int playlists, int members, int favorites, int entries) {
    return 'Import done: $playlists playlists, $members members, $favorites favorites, $entries history entries';
  }

  @override
  String dataImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get dataClearConfirmTitle => 'Clear art cache?';

  @override
  String dataClearConfirmMessage(int files) {
    return 'This deletes $files cached cover files and removes their references. Continue?';
  }

  @override
  String get dataClear => 'Clear';

  @override
  String dataArtCleared(int deleted) {
    return 'Art cache cleared: $deleted files deleted';
  }

  @override
  String dataClearFailed(String error) {
    return 'Clear art cache failed: $error';
  }

  @override
  String dataMeasureFailed(String error) {
    return 'Failed to measure art cache: $error';
  }

  @override
  String get lyricsSynced => 'Synced';

  @override
  String get lyricsPlain => 'Plain';

  @override
  String get songShare => 'Share';

  @override
  String songShareFailed(String error) {
    return 'Could not share song: $error';
  }

  @override
  String get m3uImportedDefault => 'Imported playlist';

  @override
  String m3uImportSummary(int added, int total, String name, int missing) {
    return 'Imported $added of $total songs into \"$name\" ($missing not found in library)';
  }

  @override
  String m3uImportFailed(String error) {
    return 'Import M3U failed: $error';
  }

  @override
  String get m3uImportButton => 'Import M3U';

  @override
  String get dashStreak => 'Day streak';

  @override
  String get dashTopGenreMonth => 'Top genre this month';

  @override
  String get dashCached => 'cached';

  @override
  String get recapTitle => 'Yearly Recap';

  @override
  String get recapTopArtists => 'Top artists this year';

  @override
  String get bulkCreatePlaylistFirst => 'Create a playlist first';

  @override
  String bulkActionFailed(String error) {
    return 'Action failed: $error';
  }

  @override
  String bulkFavoriteFailed(String error) {
    return 'Failed to add favorites: $error';
  }

  @override
  String bulkUnfavoriteFailed(String error) {
    return 'Failed to update favorites: $error';
  }

  @override
  String get bulkRemoveFavorite => 'Remove from favorites';

  @override
  String get albumSortTitleAZ => 'Title A-Z';

  @override
  String get albumSortTitleZA => 'Title Z-A';

  @override
  String get albumSortCountDesc => 'Most songs';

  @override
  String get albumSortCountAsc => 'Fewest songs';

  @override
  String get queueSaveTooltip => 'Save queue as playlist';

  @override
  String get queueSaveHint => 'Playlist name';

  @override
  String queueSaved(int added, int total, String name) {
    return 'Saved $added of $total songs to \"$name\"';
  }

  @override
  String queueSaveFailed(String error) {
    return 'Failed to save playlist: $error';
  }

  @override
  String get bedtimeMode => 'Bedtime';

  @override
  String bedtimeCountdownHours(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String bedtimeCountdownMinutes(int m, int s) {
    return '${m}m ${s}s';
  }

  @override
  String bedtimeCountdownSeconds(int s) {
    return '${s}s';
  }

  @override
  String bedtimeStopsIn(String countdown) {
    return 'Music stops in $countdown';
  }

  @override
  String get bedtimeAppOpenNote => 'Only works while the app stays open';

  @override
  String get bedtimePickFuture => 'Pick a bedtime in the future';

  @override
  String get recapShareTooltip => 'Share yearly recap as image';

  @override
  String get recapShareText => 'My yearly music recap';

  @override
  String recapShareFailed(String error) {
    return 'Failed to share recap image: $error';
  }

  @override
  String dupPlayFailed(String error) {
    return 'Could not play song: $error';
  }

  @override
  String get dupDeleteTitle => 'Delete selected duplicates?';

  @override
  String dupDeleteMessage(int count) {
    return 'This will delete $count songs from the library. One copy per group is kept.';
  }

  @override
  String dupRemoved(int removed, int total) {
    return 'Removed $removed of $total selected songs';
  }

  @override
  String dupDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get dupRemoveAllTitle => 'Remove all duplicates?';

  @override
  String dupRemoveAllMessage(int extras, int groups) {
    return 'This will delete $extras duplicate songs in $groups groups. One copy per group is kept.';
  }

  @override
  String dupRemovedAll(int removed, int kept) {
    return 'Removed $removed duplicate songs, kept $kept originals';
  }

  @override
  String get dupTitle => 'Duplicate Finder';

  @override
  String get dupEmpty => 'No duplicates found';

  @override
  String dupSummary(int groups, int extras) {
    return '$groups duplicate groups, $extras extra songs';
  }

  @override
  String get dupSelectExtras => 'Select extras';

  @override
  String dupSelected(int count) {
    return '$count selected';
  }

  @override
  String get dupDeleteSelected => 'Delete selected';

  @override
  String get dupKeepOne => 'Keep 1';

  @override
  String get dupKept => 'Kept';

  @override
  String get dupPlay => 'Play';

  @override
  String dupCopies(String artist, int count) {
    return '$artist - $count copies';
  }

  @override
  String get dupRemoveAll => 'Remove duplicates, keep one per group';

  @override
  String get artRefreshed => 'Cover refreshed';

  @override
  String artRefreshFailed(String error) {
    return 'Refresh failed: $error';
  }

  @override
  String artFetchStopped(int done, int total) {
    return 'Stopped early: rate limited ($done/$total)';
  }

  @override
  String artFetchFinished(int done, int total) {
    return 'Fetch finished ($done/$total)';
  }

  @override
  String artFetchFailed(String error) {
    return 'Fetch failed: $error';
  }

  @override
  String get artMissingTitle => 'Missing covers';

  @override
  String get artFetchAll => 'Fetch all';

  @override
  String get artAllHaveCovers => 'All songs have covers';

  @override
  String get artRefetch => 'Refetch cover';

  @override
  String get plFolderMoveTo => 'Move to folder';

  @override
  String get plFolderNewName => 'New folder name';

  @override
  String get plFolderRemove => 'Remove from folder';

  @override
  String get plFolderMove => 'Move';

  @override
  String get plFolderRename => 'Rename folder';

  @override
  String get plFolderDelete => 'Delete folder';

  @override
  String plFolderDeleteConfirm(String folder, int count) {
    return 'Delete folder \"$folder\"? $count playlist(s) will become ungrouped.';
  }

  @override
  String get plFolderUngrouped => 'Ungrouped';

  @override
  String get dupFinderTitle => 'Duplicate Finder';

  @override
  String dupFinderCount(int count) {
    return '$count duplicate groups';
  }

  @override
  String get artMissingEntry => 'Missing covers';

  @override
  String get m3uExportEmpty => 'Export M3U: playlist is empty';

  @override
  String m3uExported(String path) {
    return 'Exported M3U to $path';
  }

  @override
  String m3uExportFailed(String error) {
    return 'Export M3U failed: $error';
  }

  @override
  String get m3uExportMenu => 'Export M3U';

  @override
  String get hourlyTitle => 'Listening hours';

  @override
  String hourlyPeak(String hour) {
    return 'Peak $hour:00';
  }

  @override
  String get hourlyEmpty => 'No hourly data yet';

  @override
  String get histRecent => 'Recent searches';

  @override
  String get histClear => 'Clear';

  @override
  String get playerMinimize => 'Minimize';

  @override
  String get playerRepeatOff => 'Repeat off';

  @override
  String get playerRepeatAll => 'Repeat all';

  @override
  String get playerRepeatOne => 'Repeat one';

  @override
  String get queueNotFound =>
      'Could not find the new playlist. Please try again.';

  @override
  String get abTitle => 'A-B repeat';

  @override
  String get abHintInvalid => 'A must be before B and inside the song';

  @override
  String get abSetA => 'Set A';

  @override
  String get abSetB => 'Set B';

  @override
  String get abClear => 'Clear';

  @override
  String get abDone => 'Done';

  @override
  String get abHintSetB => 'A set, now set B after A';

  @override
  String get abHintSetA => 'Set A first';

  @override
  String get abHintBAfterA => 'B must be after A';

  @override
  String abOn(String a, String b) {
    return 'A-B repeat on: $a - $b';
  }

  @override
  String get abOff => 'A-B repeat off';

  @override
  String get abButton => 'A-B';

  @override
  String get abTooltip => 'A-B repeat';

  @override
  String abMarker(String a, String b) {
    return 'A-B $a - $b';
  }

  @override
  String get bulkEditValidate => 'Fill Genre or Artist first.';

  @override
  String bulkEditSummary(int ok, int failed) {
    return 'Updated $ok songs, $failed failed.';
  }

  @override
  String bulkEditTitle(int count) {
    return 'Bulk edit ($count songs)';
  }

  @override
  String get bulkEditHint => 'Leave a field empty to keep its current value.';

  @override
  String get bulkEditGenre => 'Genre';

  @override
  String get bulkEditArtist => 'Artist';

  @override
  String get bulkEditApplying => 'Applying...';

  @override
  String get bulkEditApply => 'Apply to all';

  @override
  String get bulkEditAction => 'Bulk edit';

  @override
  String get dispSection => 'Display';

  @override
  String get dispTextScale => 'Text scale';

  @override
  String get dispSmall => 'Small';

  @override
  String get dispNormal => 'Normal';

  @override
  String get dispLarge => 'Large';

  @override
  String get dispExtraLarge => 'Extra large';

  @override
  String get shortcutShuffle => 'Shuffle Favorites';

  @override
  String get shortcutContinue => 'Continue Listening';

  @override
  String get mergeNoOthers => 'No other playlists to merge from.';

  @override
  String get mergeFrom => 'Merge from...';

  @override
  String get mergeMenu => 'Merge...';

  @override
  String mergeSummary(int added, String source, String target, int skipped) {
    return 'Merged $added songs from \"$source\" into \"$target\" ($skipped already present).';
  }

  @override
  String mergeFailed(String error) {
    return 'Merge failed: $error';
  }

  @override
  String get queueClearTitle => 'Clear up next?';

  @override
  String queueClearMessage(int count) {
    return 'Remove $count song(s) after the current song? The current song is kept.';
  }

  @override
  String get queueClearAction => 'Clear';

  @override
  String queueCleared(int count) {
    return 'Cleared $count song(s) from Up Next';
  }

  @override
  String get queueClearTooltip => 'Clear up next';

  @override
  String xfDuration(int seconds) {
    return 'Crossfade duration: ${seconds}s';
  }

  @override
  String get amoledTitle => 'AMOLED black';

  @override
  String get amoledSubtitle => 'Pure black background for the dark theme';

  @override
  String get lyrRefreshed => 'Lyrics refreshed';

  @override
  String lyrRefreshFailed(String error) {
    return 'Lyrics refresh failed: $error';
  }

  @override
  String lyrFetchStopped(int done, int total) {
    return 'Stopped early: rate limited ($done/$total)';
  }

  @override
  String lyrFetchFinished(int done, int total) {
    return 'Fetch finished ($done/$total)';
  }

  @override
  String lyrFetchFailed(String error) {
    return 'Lyrics fetch failed: $error';
  }

  @override
  String get lyrMissingTitle => 'Missing lyrics';

  @override
  String get lyrFetchAll => 'Fetch all';

  @override
  String get lyrAllHave => 'All songs have lyrics';

  @override
  String get lyrRefetch => 'Refetch lyrics';

  @override
  String get missLyricsEntry => 'Missing lyrics';

  @override
  String get librarySelectAll => 'Select all';

  @override
  String get libraryClearSelection => 'Clear selection';

  @override
  String get libraryJumpPlaying => 'Jump to playing song';

  @override
  String get playerSpeed => 'Speed';

  @override
  String get playerPitch => 'Pitch';

  @override
  String get playerSpeedPitchReset => 'Reset';

  @override
  String get settingsSmartShuffle => 'Smart shuffle';

  @override
  String get settingsSmartShuffleSubtitle =>
      'Play rarely played and long unplayed songs first';

  @override
  String get sleepDailySchedule => 'Daily schedule';

  @override
  String get sleepDailyScheduleSubtitle =>
      'Auto start a 30 minute sleep timer every day';

  @override
  String get sleepDailyScheduleSetTime => 'Set time';

  @override
  String get sleepDailyScheduleHint =>
      'Starts the timer only when the app is open';

  @override
  String get editLyricsSearchOpenFailed => 'Could not open the browser';

  @override
  String librarySelectAllTooMany(int limit) {
    return 'Too many songs to select all at once. Select up to $limit songs.';
  }

  @override
  String libraryPartialAddedToPlaylist(
      int added, int total, String name, int failed) {
    return 'Added $added of $total songs to $name, $failed failed.';
  }

  @override
  String libraryFavoritesAdded(int count) {
    return '$count songs added to favorites';
  }

  @override
  String get historyCleanupTitle => 'Clean up listening history';

  @override
  String get historyCleanupSubtitle =>
      'Delete old listening history older than 12 months and cap the total rows';

  @override
  String get historyCleanupDialogTitle => 'Delete old listening history?';

  @override
  String get historyCleanupMessage =>
      'Listening history older than 12 months will be deleted, and the oldest rows will be removed until at most 200,000 rows remain. Dashboard totals such as Total listened and Top songs are based on this history, so those numbers will go down.';

  @override
  String get historyCleanupAction => 'Delete';

  @override
  String historyCleanupDone(int count) {
    return 'Deleted $count history rows';
  }

  @override
  String historyCleanupFailed(String error) {
    return 'History cleanup failed: $error';
  }

  @override
  String get editMetadataRescanRateLimited =>
      'Fetch skipped, too many requests. Try again in a minute.';

  @override
  String historyPlayFailed(String error) {
    return 'Could not play this song: $error';
  }

  @override
  String get playerLyricTiming => 'Lyric timing';

  @override
  String get playerLyricTimingEarlier => 'Shift lyrics 100 ms earlier';

  @override
  String get playerLyricTimingLater => 'Shift lyrics 100 ms later';

  @override
  String get eqActive => 'EQ active';

  @override
  String get eqUnavailable => 'EQ unavailable on this device';

  @override
  String searchDidYouMean(String suggestion) {
    return 'Did you mean \"$suggestion\"?';
  }
}
