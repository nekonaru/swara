// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get settingsTitle => 'Pengaturan';

  @override
  String get settingsAppearance => 'Tampilan';

  @override
  String get settingsFollowSystem => 'Ikuti sistem';

  @override
  String get settingsLight => 'Terang';

  @override
  String get settingsDark => 'Gelap';

  @override
  String get settingsAccentColor => 'Warna Aksen';

  @override
  String get settingsAccentPurple => 'Ungu';

  @override
  String get settingsAccentBlue => 'Biru';

  @override
  String get settingsAccentTeal => 'Teal';

  @override
  String get settingsAccentGreen => 'Hijau';

  @override
  String get settingsAccentOrange => 'Oranye';

  @override
  String get settingsAccentRed => 'Merah';

  @override
  String get settingsAccentDeepPurple => 'Ungu Tua';

  @override
  String get settingsAccentPink => 'Pink';

  @override
  String get settingsAccentCyan => 'Cyan';

  @override
  String get settingsAccentLightGreen => 'Hijau Muda';

  @override
  String get settingsPlayback => 'Pemutaran';

  @override
  String get settingsCrossfade => 'Crossfade';

  @override
  String get settingsCrossfadeSubtitle =>
      'Transisi antar lagu tanpa jeda (3 detik)';

  @override
  String get settingsEqualizer => 'Equalizer';

  @override
  String get settingsEqualizerNote =>
      'Preset ini membentuk suara putar yang sebenarnya lewat equalizer sistem. Pilihan disimpan antar sesi.';

  @override
  String get settingsLibrary => 'Library';

  @override
  String get settingsScanFiles => 'Pindai File Musik';

  @override
  String get settingsScanFilesSubtitle =>
      'Cek file musik baru/dihapus di HP (tanpa internet)';

  @override
  String get settingsScanMissing => 'Scan Metadata yang Belum Ada';

  @override
  String get settingsScanMissingSubtitle =>
      'Ambil judul/artis/cover dari internet untuk lagu baru';

  @override
  String settingsScanProgress(int progress, int total) {
    return 'Memproses $progress/$total...';
  }

  @override
  String get settingsRescanAll => 'Scan Ulang Semua Metadata';

  @override
  String get settingsRescanAllSubtitle =>
      'Ambil ulang dari internet untuk SEMUA lagu';

  @override
  String get settingsAbout => 'Tentang';

  @override
  String settingsAboutVersion(String version) {
    return 'v$version';
  }

  @override
  String get settingsDeveloper => 'Developer';

  @override
  String get settingsDeveloperName => 'Nicolas Dwi Dharma';

  @override
  String get settingsRescanTitle => 'Scan Ulang Semua';

  @override
  String settingsRescanMessage(int count) {
    return 'Ambil ulang metadata untuk semua $count lagu dari internet? Ini butuh waktu lebih lama.';
  }

  @override
  String get settingsRescanStart => 'Mulai';

  @override
  String get languageSection => 'Bahasa';

  @override
  String get languageSubtitle => 'Bahasa aplikasi';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Batal';

  @override
  String get retry => 'Coba lagi';

  @override
  String get close => 'Tutup';

  @override
  String get save => 'Simpan';

  @override
  String get delete => 'Hapus';

  @override
  String get edit => 'Edit';

  @override
  String get remove => 'Hapus';

  @override
  String get add => 'Tambah';

  @override
  String get create => 'Buat';

  @override
  String get search => 'Cari';

  @override
  String get loading => 'Memuat...';

  @override
  String get error => 'Terjadi kesalahan';

  @override
  String get empty => 'Belum ada apa-apa';

  @override
  String get confirm => 'Konfirmasi';

  @override
  String get yes => 'Ya';

  @override
  String get no => 'Tidak';

  @override
  String get unknown => 'Tidak diketahui';

  @override
  String get failed => 'Gagal';

  @override
  String get corePlayFailed => 'Gagal memutar';

  @override
  String get coreScanFailed => 'Gagal memindai';

  @override
  String get coreUpdateFavoritesFailed => 'Gagal mengubah favorit';

  @override
  String get coreSongAlreadyInPlaylist => 'Lagu sudah ada di playlist ini';

  @override
  String get coreRemoveFromPlaylistFailed =>
      'Gagal menghapus lagu dari playlist';

  @override
  String get coreSavePlaylistOrderFailed => 'Gagal menyimpan urutan playlist';

  @override
  String get corePermissionDenied => 'Izin akses musik ditolak';

  @override
  String get coreSongs => 'lagu';

  @override
  String playlistLoadFailed(String error) {
    return 'Gagal memuat playlist: $error';
  }

  @override
  String playlistReorderFailed(String error) {
    return 'Gagal menyimpan urutan: $error';
  }

  @override
  String playlistRemoveFailed(String error) {
    return 'Gagal menghapus lagu: $error';
  }

  @override
  String get playlistSortCustom => 'Urutan kustom';

  @override
  String get playlistSortTitleAZ => 'Judul A-Z';

  @override
  String get playlistSortTitleZA => 'Judul Z-A';

  @override
  String get playlistSortArtistAZ => 'Artis A-Z';

  @override
  String get playlistEmpty => 'Playlist ini masih kosong';

  @override
  String playlistSummary(int count, String duration) {
    return '$count lagu · $duration';
  }

  @override
  String get playlistSearchHint => 'Cari di playlist ini...';

  @override
  String get playlistPlay => 'Mulai Putar';

  @override
  String get playlistShuffle => 'Acak';

  @override
  String get playlistReorderHint => 'Tahan dan geser untuk mengatur urutan';

  @override
  String get playlistNoResults => 'Lagu tidak ditemukan';

  @override
  String historyLoadFailed(String error) {
    return 'Gagal memuat riwayat: $error';
  }

  @override
  String get historyEmpty => 'Belum ada riwayat pemutaran';

  @override
  String get dashboardLoadFailedTitle => 'Gagal memuat dashboard';

  @override
  String get dashboardRetry => 'Coba Lagi';

  @override
  String get dashboardEmptyTitle => 'Dashboard kosong';

  @override
  String get dashboardEmptySubtitle =>
      'Statistik pendengaran akan muncul setelah kamu mulai memutar lagu.';

  @override
  String get dashboardTotalSongsLibrary => 'Total lagu di library';

  @override
  String get dashboardTotalSongs => 'Total lagu';

  @override
  String get dashboardTotalListened => 'Total didengar';

  @override
  String get dashboardThisMonth => 'Bulan ini';

  @override
  String dashboardHoursValue(String hours) {
    return '$hours jam';
  }

  @override
  String get dashboardListeningWeekTitle => 'Jam Dengar 7 Hari Terakhir';

  @override
  String dashboardWeekTotal(String hours) {
    return '$hours jam total';
  }

  @override
  String get dashboardTopSongs => 'Top 5 Lagu';

  @override
  String dashboardUnknownSong(int id) {
    return 'Lagu #$id';
  }

  @override
  String dashboardPlayCount(int count) {
    return '${count}x diputar';
  }

  @override
  String dashboardPlayFailed(String error) {
    return 'Gagal memutar lagu: $error';
  }

  @override
  String get dashboardTopArtists => 'Top 5 Artis';

  @override
  String get dashboardGenreTitle => 'Distribusi Genre';

  @override
  String dashboardGenreCount(int count) {
    return '$count genre';
  }

  @override
  String get dashboardNeverPlayedTitle => 'Belum Pernah Diputar';

  @override
  String dashboardSongCount(int count) {
    return '$count lagu';
  }

  @override
  String dashboardNeverPlayedSubtitle(int count) {
    return '$count lagu di library kamu belum pernah diputar.';
  }

  @override
  String get dashboardPlayAll => 'Putar Semua';

  @override
  String get dashboardWeekActivityTitle => 'Aktivitas Minggu Ini';

  @override
  String get dashboardNoWeekActivity => 'Belum ada aktivitas minggu ini.';

  @override
  String dashboardActiveDays(int count) {
    return '$count dari 7 hari aktif mendengarkan';
  }

  @override
  String dashboardNeverPlayedSheetTitle(int count) {
    return '$count lagu belum pernah diputar';
  }

  @override
  String get dashboardDaySun => 'Min';

  @override
  String get dashboardDayMon => 'Sen';

  @override
  String get dashboardDayTue => 'Sel';

  @override
  String get dashboardDayWed => 'Rab';

  @override
  String get dashboardDayThu => 'Kam';

  @override
  String get dashboardDayFri => 'Jum';

  @override
  String get dashboardDaySat => 'Sab';

  @override
  String dashboardTooltipMinutes(int mins) {
    return '${mins}m';
  }

  @override
  String dashboardTooltipHours(String hours) {
    return '${hours}j';
  }

  @override
  String get editMetadataValidationEmpty =>
      'Judul, artis, dan album tidak boleh kosong';

  @override
  String editMetadataSaveFailed(String error) {
    return 'Gagal menyimpan: $error';
  }

  @override
  String get editMetadataRescanTitle => 'Scan Ulang dari Internet?';

  @override
  String get editMetadataRescanMessage =>
      'Data dari internet akan menimpa edit manual Anda di form ini. Lanjutkan?';

  @override
  String get editMetadataRescanConfirm => 'Ya, Timpa';

  @override
  String editMetadataRescanFailed(String error) {
    return 'Gagal scan ulang: $error';
  }

  @override
  String get editMetadataRescanSuccess =>
      'Metadata berhasil diperbarui dari internet';

  @override
  String get editMetadataTitle => 'Edit Metadata';

  @override
  String get editMetadataFetching => 'Mengambil data...';

  @override
  String get editMetadataRescanButton => 'Scan Ulang dari Internet';

  @override
  String get editMetadataFieldTitle => 'Judul';

  @override
  String get editMetadataFieldArtist => 'Artis';

  @override
  String get editMetadataFieldAlbum => 'Album';

  @override
  String get editMetadataFieldGenre => 'Genre';

  @override
  String get editMetadataFieldRegion => 'Asal Region';

  @override
  String get editMetadataEditLyricsButton => 'Edit Lirik (halaman terpisah)';

  @override
  String get editMetadataSaveButton => 'Simpan Perubahan';

  @override
  String get editLyricsClipboardEmpty =>
      'Clipboard kosong, tidak ada teks untuk ditempel';

  @override
  String get editLyricsPasteTitle => 'Tempel Lirik';

  @override
  String get editLyricsPasteMessage =>
      'Sudah ada lirik di sini. Mau ditimpa (mulai dari nol) atau ditambahkan ke lirik yang ada?';

  @override
  String get editLyricsAppend => 'Tambahkan';

  @override
  String get editLyricsOverwrite => 'Timpa';

  @override
  String editLyricsSaveFailed(String error) {
    return 'Gagal menyimpan lirik: $error';
  }

  @override
  String get editLyricsTruncated =>
      'Lirik melebihi 100KB dan dipotong saat disimpan';

  @override
  String editLyricsTitle(String title) {
    return 'Edit Lirik: $title';
  }

  @override
  String get editLyricsPasteButton => 'Tempelkan';

  @override
  String get editLyricsSearchWeb => 'Cari di Web';

  @override
  String get editLyricsHint =>
      'Belum ada lirik. Tempel dari clipboard, cari di web, atau ketik manual di sini.';

  @override
  String get editLyricsSaveButton => 'Simpan Lirik';

  @override
  String get songOptionsPlayNext => 'Putar Berikutnya';

  @override
  String get songOptionsAddedPlayNext => 'Ditambahkan untuk diputar berikutnya';

  @override
  String get songOptionsAddToQueueEnd => 'Tambah ke Akhir Antrean';

  @override
  String get songOptionsAddedToQueue => 'Ditambahkan ke antrean';

  @override
  String get songOptionsAddFavorite => 'Tambah ke Favorit';

  @override
  String get songOptionsRemoveFavorite => 'Hapus dari Favorit';

  @override
  String songOptionsFavoriteFailed(String error) {
    return 'Gagal update favorit: $error';
  }

  @override
  String get songOptionsAddToPlaylist => 'Tambah ke Playlist';

  @override
  String get songOptionsRename => 'Ganti Nama Lagu';

  @override
  String get songOptionsEditMetadata => 'Edit Metadata';

  @override
  String get songOptionsRemoveFromPlaylist => 'Hapus dari Playlist Ini';

  @override
  String songOptionsRemoveFromPlaylistFailed(String error) {
    return 'Gagal hapus dari playlist: $error';
  }

  @override
  String get songOptionsRemovedFromPlaylist => 'Dihapus dari playlist ini saja';

  @override
  String get songOptionsDeleteFromLibrary => 'Hapus dari Library';

  @override
  String get songOptionsDeleteTitle => 'Hapus Lagu';

  @override
  String songOptionsDeleteConfirm(String title) {
    return 'Hapus \"$title\" dari Semua Lagu, Folder, Favorit, dan Playlist? File asli di HP tidak terhapus - lagu ini akan muncul lagi kalau folder di-scan ulang.';
  }

  @override
  String songOptionsDeleteFailed(String error) {
    return 'Gagal hapus lagu: $error';
  }

  @override
  String songOptionsRenameFailed(String error) {
    return 'Gagal ganti nama: $error';
  }

  @override
  String get songOptionsCreatePlaylist => 'Buat Playlist Baru';

  @override
  String get songOptionsPlaylistNameTitle => 'Nama Playlist';

  @override
  String songOptionsAddToPlaylistFailed(String error) {
    return 'Gagal tambah ke playlist: $error';
  }

  @override
  String songOptionsPlaylistCreated(String name) {
    return 'Playlist \"$name\" dibuat & lagu ditambahkan';
  }

  @override
  String songOptionsPlaylistExists(String name) {
    return 'Playlist \"$name\" sudah ada, pilih dari daftar';
  }

  @override
  String songOptionsCreatePlaylistFailed(String error) {
    return 'Gagal membuat playlist: $error';
  }

  @override
  String get librarySortBy => 'Urutkan berdasarkan';

  @override
  String get librarySortTitleAsc => 'Judul ↑';

  @override
  String get librarySortTitleDesc => 'Judul ↓';

  @override
  String get librarySortArtistAsc => 'Artis ↑';

  @override
  String get librarySortArtistDesc => 'Artis ↓';

  @override
  String get librarySortAlbumAsc => 'Album ↑';

  @override
  String get librarySortAlbumDesc => 'Album ↓';

  @override
  String get librarySortDateNewest => 'Tanggal ↑';

  @override
  String get librarySortDateOldest => 'Tanggal ↓';

  @override
  String get librarySortGenre => 'Genre ↑';

  @override
  String get libraryCreatePlaylistFirst => 'Buat playlist dulu di tab Koleksi';

  @override
  String get libraryChoosePlaylist => 'Pilih playlist';

  @override
  String libraryAddedToPlaylist(int count, String name) {
    return '$count lagu ditambahkan ke $name';
  }

  @override
  String librarySelectedCount(int count) {
    return '$count dipilih';
  }

  @override
  String get libraryAddToPlaylist => 'Tambah ke playlist';

  @override
  String get libraryAddToFavorites => 'Tambah ke favorit';

  @override
  String librarySongCount(int count) {
    return '$count lagu';
  }

  @override
  String librarySongCountDuration(int count, String duration) {
    return '$count lagu · $duration';
  }

  @override
  String get libraryScanMetadata => 'Scan metadata';

  @override
  String get libraryStartPlaying => 'Mulai Putar';

  @override
  String get libraryShuffle => 'Acak';

  @override
  String get libraryScanningMusic => 'Memindai musik...';

  @override
  String get libraryNoMusic => 'Belum ada musik';

  @override
  String get libraryScanMusic => 'Pindai Musik';

  @override
  String get libraryScanMissing => 'Scan yang Belum Ada Metadata';

  @override
  String get libraryRescanAll => 'Scan Ulang Semua';

  @override
  String libraryRescanConfirm(int count) {
    return 'Ambil ulang metadata untuk $count lagu?';
  }

  @override
  String get libraryStart => 'Mulai';

  @override
  String libraryPlayFailed(String error) {
    return 'Gagal memutar lagu: $error';
  }

  @override
  String get searchHint => 'Cari musik...';

  @override
  String get searchFilterSong => 'Lagu';

  @override
  String get searchFilterAlbum => 'Album';

  @override
  String get searchFilterArtist => 'Artis';

  @override
  String get searchFilterFolder => 'Folder';

  @override
  String get searchFilterGenre => 'Genre';

  @override
  String get searchPromptTitle => 'Cari musik kamu';

  @override
  String get searchPromptSubtitle => 'Ketik judul, artis, album, atau lainnya';

  @override
  String get searchNoResults => 'Tidak ada hasil';

  @override
  String searchNotFound(String query) {
    return '\"$query\" tidak ditemukan';
  }

  @override
  String searchResultCount(int count) {
    return '$count hasil';
  }

  @override
  String get searchOther => 'Lainnya';

  @override
  String get albumsEmpty => 'Belum ada data album.';

  @override
  String albumsCount(int count) {
    return '$count album';
  }

  @override
  String get collectionsNewPlaylist => 'Playlist Baru';

  @override
  String get collectionsPlaylistNameHint => 'Nama playlist';

  @override
  String get collectionsDeletePlaylist => 'Hapus Playlist';

  @override
  String collectionsDeleteConfirm(String name) {
    return 'Hapus \"$name\"?';
  }

  @override
  String collectionsDeletePlaylistConfirm(String name) {
    return 'Hapus playlist \"$name\"?';
  }

  @override
  String get collectionsFavorites => 'Favorit';

  @override
  String get collectionsRecentlyAdded => 'Baru ditambahkan';

  @override
  String get collectionsRecentlyPlayed => 'Baru diputar';

  @override
  String get collectionsMostPlayed => 'Paling sering diputar';

  @override
  String get collectionsRecentlyAddedTitle => 'Baru Ditambahkan';

  @override
  String get collectionsRecentlyPlayedTitle => 'Baru Diputar';

  @override
  String get collectionsMostPlayedTitle => 'Paling Sering Diputar';

  @override
  String get collectionsSortNameAsc => 'Nama ↑';

  @override
  String get collectionsSortNameDesc => 'Nama ↓';

  @override
  String collectionsPlaylistCount(int count) {
    return '$count daftar putar';
  }

  @override
  String collectionsPlaylistCountAlt(int count) {
    return '$count playlist';
  }

  @override
  String get collectionsNoPlaylists => 'Belum ada playlist';

  @override
  String get collectionsCreatePlaylist => 'Buat Playlist';

  @override
  String get collectionsFavoritesEmpty => 'Belum ada favorit';

  @override
  String get collectionsFavoritesHint =>
      'Tekan ikon hati pada lagu untuk menambahkan';

  @override
  String get collectionsRecentlyAddedEmpty =>
      'Belum ada lagu yang ditambahkan.';

  @override
  String get collectionsMostPlayedEmpty => 'Belum ada data pemutaran';

  @override
  String get collectionsMostPlayedHint =>
      'Mulai putar lagu untuk melihat statistik';

  @override
  String foldersLoadFailed(String error) {
    return 'Gagal memuat folder: $error';
  }

  @override
  String get foldersShownAgain => 'Folder ditampilkan lagi';

  @override
  String get foldersHidden => 'Folder disembunyikan dari library';

  @override
  String get foldersEmpty => 'Belum ada folder musik terdeteksi.';

  @override
  String foldersCount(int count) {
    return '$count folder';
  }

  @override
  String get foldersSortNameAsc => 'Nama ↑';

  @override
  String get foldersSortNameDesc => 'Nama ↓';

  @override
  String get foldersSortCount => 'Jumlah lagu';

  @override
  String get foldersSortCountShort => 'Jumlah';

  @override
  String get foldersHideHidden => 'Sembunyikan folder tersembunyi';

  @override
  String get foldersShowHidden => 'Tampilkan folder tersembunyi';

  @override
  String get foldersNoSongs => 'Tidak ada lagu';

  @override
  String get foldersAllScanned =>
      'Semua lagu di folder ini sudah pernah discan';

  @override
  String get foldersScanDone => 'Selesai scan metadata folder ini';

  @override
  String get foldersSortTitleAsc => 'Judul ↑';

  @override
  String get foldersSortTitleDesc => 'Judul ↓';

  @override
  String get foldersSortArtistAsc => 'Artis ↑';

  @override
  String get foldersSortDate => 'Tanggal ↑';

  @override
  String get artistsEmpty => 'Belum ada data artis.';

  @override
  String artistsCount(int count) {
    return '$count artis';
  }

  @override
  String get genresEmpty => 'Belum ada data genre.';

  @override
  String genresCount(int count) {
    return '$count genre';
  }

  @override
  String get homeLibrary => 'Perpustakaan';

  @override
  String get homeCollection => 'Koleksi';

  @override
  String get homeDashboard => 'Dashboard';

  @override
  String get homeTabSongs => 'Lagu';

  @override
  String get homeTabAlbums => 'Album';

  @override
  String get homeTabArtists => 'Artis';

  @override
  String get homeTabFolders => 'Folder';

  @override
  String get homeTabGenres => 'Genre';

  @override
  String get homeTabSettings => 'Pengaturan tab';

  @override
  String get homeTabReorderHint => 'Seret tab untuk mengubah urutan';

  @override
  String get homeReset => 'Atur Ulang';

  @override
  String get homeApply => 'Terapkan';

  @override
  String get homeMinOneTab => 'Minimal 1 tab harus aktif';

  @override
  String get homeSettings => 'Pengaturan';

  @override
  String homeLoadLibraryFailed(String error) {
    return 'Gagal memuat library: $error';
  }

  @override
  String get homePressAgainToExit => 'Tekan sekali lagi untuk keluar';

  @override
  String get playerPlaybackSpeed => 'Kecepatan Putar';

  @override
  String get playerCannotOpenBrowser => 'Tidak bisa membuka browser';

  @override
  String get playerSearchOpenFailed => 'Gagal membuka pencarian';

  @override
  String get playerLyricsFound => 'Lirik ditemukan!';

  @override
  String get playerLyricsNotFoundHint =>
      'Lirik tetap tidak ditemukan, coba tambah manual';

  @override
  String playerSongsRemaining(int count) {
    return '$count lagu lagi';
  }

  @override
  String get playerEmptyState => 'Belum ada lagu diputar';

  @override
  String get playerTapToReturnToCover => 'Ketuk untuk kembali ke cover';

  @override
  String get playerEditLyrics => 'Edit Lirik';

  @override
  String get playerLyricsNotFound => 'Lirik tidak ditemukan';

  @override
  String get playerTapHereToReturnToCover =>
      'Ketuk di sini untuk kembali ke cover';

  @override
  String get playerSearchOnGoogle => 'Cari di Google';

  @override
  String get playerAutoSearch => 'Cari Otomatis';

  @override
  String get playerAddManually => 'Tambah Manual';

  @override
  String get playerPrevious => 'Sebelumnya';

  @override
  String get playerNext => 'Berikutnya';

  @override
  String get playerFavorite => 'Favorit';

  @override
  String get playerAddToPlaylist => 'Tambah ke Playlist';

  @override
  String get playerSleepTimer => 'Timer Tidur';

  @override
  String get queueTitle => 'Antrean Putar';

  @override
  String get queueEmpty => 'Antrean kosong';

  @override
  String get queueReorderHint =>
      'Tahan-geser untuk urutkan · geser ke kiri untuk hapus';

  @override
  String get sleepTitle => 'Timer tidur';

  @override
  String get sleepSetTimeAboveZero => 'Set waktu lebih dari 0';

  @override
  String get sleepRemaining => 'tersisa';

  @override
  String get sleepFinishLastSong => 'Selesaikan lagu terakhir';

  @override
  String get sleepSongsRemaining => 'lagu tersisa';

  @override
  String get sleepStop => 'Berhenti';

  @override
  String get sleepTimeMode => 'Waktu';

  @override
  String get sleepSongMode => 'Lagu';

  @override
  String get sleepStart => 'Mulai';

  @override
  String get sleepSongUnit => 'lagu';

  @override
  String get sleepTimerStopped => 'Timer tidur dihentikan';

  @override
  String loadMore(int shown, int total) {
    return 'Muat lagi ($shown dari $total)';
  }

  @override
  String get sleepFadingOut => 'Memudar...';

  @override
  String get sleepStoppingPlayback => 'Menghentikan pemutaran';

  @override
  String autoPlaylistError(String error) {
    return 'Gagal memperbarui playlist otomatis: $error';
  }

  @override
  String get autoBadge => 'Otomatis';

  @override
  String get reshuffleDailyMix => 'Acak Ulang Campuran Harian';

  @override
  String get reshuffle => 'Acak Ulang';

  @override
  String get onboardSkip => 'Lewati';

  @override
  String get onboardNext => 'Lanjut';

  @override
  String get onboardGetStarted => 'Mulai';

  @override
  String get onboardTitle1 => 'Selamat datang di Swara';

  @override
  String get onboardDesc1 =>
      'Pemutar musik offline-mu. Izinkan akses audio agar Swara dapat menampilkan lagu yang sudah ada di perangkat.';

  @override
  String get onboardTitle2 => 'Metadata dan lirik otomatis';

  @override
  String get onboardDesc2 =>
      'Swara melengkapi cover album, info artis, dan lirik yang hilang secara otomatis agar library selalu tampil lengkap.';

  @override
  String get onboardTitle3 => 'Siap mendengarkan';

  @override
  String get onboardDesc3 =>
      'Jelajahi lagu, susun playlist, dan cek statistik mendengarkan di dashboard. Ketuk Mulai untuk memulai.';

  @override
  String get dataSection => 'Data';

  @override
  String get dataExport => 'Export backup';

  @override
  String get dataExportSubtitle =>
      'Salin playlist, favorit, dan riwayat sebagai JSON';

  @override
  String get dataImport => 'Import backup';

  @override
  String get dataImportSubtitle => 'Pulihkan dari JSON backup yang ditempel';

  @override
  String get dataArtCache => 'Cache cover album';

  @override
  String get dataArtCacheMeasuring => 'Mengukur cache...';

  @override
  String dataArtCacheUsage(String bytes, int files) {
    return '$bytes dalam $files file';
  }

  @override
  String get dataRefresh => 'Segarkan';

  @override
  String get dataClearArtCache => 'Bersihkan cache cover';

  @override
  String get dataClearArtCacheSubtitle =>
      'Hapus file cover dan bersihkan referensi';

  @override
  String get dataExportTitle => 'Export backup';

  @override
  String dataExportReady(int chars, String size) {
    return 'Backup siap: $chars karakter, $size. Salin ke clipboard agar aman.';
  }

  @override
  String get dataCopy => 'Salin';

  @override
  String get dataCopied => 'Backup tersalin ke clipboard';

  @override
  String dataExportFailed(String error) {
    return 'Export gagal: $error';
  }

  @override
  String get dataImportTitle => 'Import backup';

  @override
  String get dataImportPrompt =>
      'Tempel string JSON backup, atau muat dari clipboard.';

  @override
  String get dataImportHint => 'Tempel JSON backup di sini';

  @override
  String get dataPaste => 'Tempel';

  @override
  String get dataImportAction => 'Import';

  @override
  String get dataConfirmImportTitle => 'Konfirmasi import';

  @override
  String get dataConfirmImportMessage =>
      'Import akan menambah playlist, favorit, dan entri riwayat yang belum ada. Lanjut?';

  @override
  String dataImportDone(
      int playlists, int members, int favorites, int entries) {
    return 'Import selesai: $playlists playlist, $members anggota, $favorites favorit, $entries entri riwayat';
  }

  @override
  String dataImportFailed(String error) {
    return 'Import gagal: $error';
  }

  @override
  String get dataClearConfirmTitle => 'Bersihkan cache cover?';

  @override
  String dataClearConfirmMessage(int files) {
    return 'Ini menghapus $files file cover cache dan referensinya. Lanjut?';
  }

  @override
  String get dataClear => 'Bersihkan';

  @override
  String dataArtCleared(int deleted) {
    return 'Cache cover dibersihkan: $deleted file dihapus';
  }

  @override
  String dataClearFailed(String error) {
    return 'Gagal membersihkan cache cover: $error';
  }

  @override
  String dataMeasureFailed(String error) {
    return 'Gagal mengukur cache cover: $error';
  }

  @override
  String get lyricsSynced => 'Sinkron';

  @override
  String get lyricsPlain => 'Biasa';

  @override
  String get songShare => 'Bagikan';

  @override
  String songShareFailed(String error) {
    return 'Tidak bisa membagikan lagu: $error';
  }

  @override
  String get m3uImportedDefault => 'Playlist import';

  @override
  String m3uImportSummary(int added, int total, String name, int missing) {
    return 'Mengimpor $added dari $total lagu ke \"$name\" ($missing tidak ketemu di library)';
  }

  @override
  String m3uImportFailed(String error) {
    return 'Import M3U gagal: $error';
  }

  @override
  String get m3uImportButton => 'Import M3U';

  @override
  String get dashStreak => 'Streak harian';

  @override
  String get dashTopGenreMonth => 'Genre teratas bulan ini';

  @override
  String get dashCached => 'cache';

  @override
  String get recapTitle => 'Rekap Tahunan';

  @override
  String get recapTopArtists => 'Artis teratas tahun ini';

  @override
  String get bulkCreatePlaylistFirst => 'Buat playlist dulu';

  @override
  String bulkActionFailed(String error) {
    return 'Aksi gagal: $error';
  }

  @override
  String bulkFavoriteFailed(String error) {
    return 'Gagal menambah favorit: $error';
  }

  @override
  String bulkUnfavoriteFailed(String error) {
    return 'Gagal memperbarui favorit: $error';
  }

  @override
  String get bulkRemoveFavorite => 'Hapus dari favorit';

  @override
  String get albumSortTitleAZ => 'Judul A-Z';

  @override
  String get albumSortTitleZA => 'Judul Z-A';

  @override
  String get albumSortCountDesc => 'Lagu terbanyak';

  @override
  String get albumSortCountAsc => 'Lagu tersedikit';

  @override
  String get queueSaveTooltip => 'Simpan antrean sebagai playlist';

  @override
  String get queueSaveHint => 'Nama playlist';

  @override
  String queueSaved(int added, int total, String name) {
    return 'Menyimpan $added dari $total lagu ke \"$name\"';
  }

  @override
  String queueSaveFailed(String error) {
    return 'Gagal menyimpan playlist: $error';
  }

  @override
  String get bedtimeMode => 'Waktu tidur';

  @override
  String bedtimeCountdownHours(int h, int m) {
    return '$h jam $m mnt';
  }

  @override
  String bedtimeCountdownMinutes(int m, int s) {
    return '$m mnt $s dtk';
  }

  @override
  String bedtimeCountdownSeconds(int s) {
    return '$s dtk';
  }

  @override
  String bedtimeStopsIn(String countdown) {
    return 'Musik berhenti dalam $countdown';
  }

  @override
  String get bedtimeAppOpenNote => 'Hanya berlaku selama aplikasi terbuka';

  @override
  String get bedtimePickFuture => 'Pilih jam tidur yang akan datang';

  @override
  String get recapShareTooltip => 'Bagikan rekap tahunan sebagai gambar';

  @override
  String get recapShareText => 'Rekap musik tahunanku';

  @override
  String recapShareFailed(String error) {
    return 'Gagal membagikan gambar rekap: $error';
  }

  @override
  String dupPlayFailed(String error) {
    return 'Tidak bisa memutar lagu: $error';
  }

  @override
  String get dupDeleteTitle => 'Hapus duplikat terpilih?';

  @override
  String dupDeleteMessage(int count) {
    return 'Ini akan menghapus $count lagu dari library. Satu salinan per grup dipertahankan.';
  }

  @override
  String dupRemoved(int removed, int total) {
    return 'Menghapus $removed dari $total lagu terpilih';
  }

  @override
  String dupDeleteFailed(String error) {
    return 'Hapus gagal: $error';
  }

  @override
  String get dupRemoveAllTitle => 'Hapus semua duplikat?';

  @override
  String dupRemoveAllMessage(int extras, int groups) {
    return 'Ini akan menghapus $extras lagu duplikat dalam $groups grup. Satu salinan per grup dipertahankan.';
  }

  @override
  String dupRemovedAll(int removed, int kept) {
    return 'Menghapus $removed lagu duplikat, $kept asli dipertahankan';
  }

  @override
  String get dupTitle => 'Pencari Duplikat';

  @override
  String get dupEmpty => 'Tidak ada duplikat';

  @override
  String dupSummary(int groups, int extras) {
    return '$groups grup duplikat, $extras lagu ekstra';
  }

  @override
  String get dupSelectExtras => 'Pilih ekstra';

  @override
  String dupSelected(int count) {
    return '$count terpilih';
  }

  @override
  String get dupDeleteSelected => 'Hapus terpilih';

  @override
  String get dupKeepOne => 'Sisakan 1';

  @override
  String get dupKept => 'Dipertahankan';

  @override
  String get dupPlay => 'Putar';

  @override
  String dupCopies(String artist, int count) {
    return '$artist - $count duplikat';
  }

  @override
  String get dupRemoveAll => 'Hapus duplikat, sisakan satu per grup';

  @override
  String get artRefreshed => 'Cover tersegarkan';

  @override
  String artRefreshFailed(String error) {
    return 'Segarkan gagal: $error';
  }

  @override
  String artFetchStopped(int done, int total) {
    return 'Berhenti dini: rate limited ($done/$total)';
  }

  @override
  String artFetchFinished(int done, int total) {
    return 'Fetch selesai ($done/$total)';
  }

  @override
  String artFetchFailed(String error) {
    return 'Fetch gagal: $error';
  }

  @override
  String get artMissingTitle => 'Cover hilang';

  @override
  String get artFetchAll => 'Fetch semua';

  @override
  String get artAllHaveCovers => 'Semua lagu sudah bercover';

  @override
  String get artRefetch => 'Fetch ulang cover';

  @override
  String get plFolderMoveTo => 'Pindah ke folder';

  @override
  String get plFolderNewName => 'Nama folder baru';

  @override
  String get plFolderRemove => 'Keluarkan dari folder';

  @override
  String get plFolderMove => 'Pindah';

  @override
  String get plFolderRename => 'Ganti nama folder';

  @override
  String get plFolderDelete => 'Hapus folder';

  @override
  String plFolderDeleteConfirm(String folder, int count) {
    return 'Hapus folder \"$folder\"? $count playlist tidak berkelompok.';
  }

  @override
  String get plFolderUngrouped => 'Tanpa folder';

  @override
  String get dupFinderTitle => 'Pencari Duplikat';

  @override
  String dupFinderCount(int count) {
    return '$count grup duplikat';
  }

  @override
  String get artMissingEntry => 'Cover hilang';

  @override
  String get m3uExportEmpty => 'Export M3U: playlist kosong';

  @override
  String m3uExported(String path) {
    return 'M3U diekspor ke $path';
  }

  @override
  String m3uExportFailed(String error) {
    return 'Export M3U gagal: $error';
  }

  @override
  String get m3uExportMenu => 'Export M3U';

  @override
  String get hourlyTitle => 'Jam dengar';

  @override
  String hourlyPeak(String hour) {
    return 'Puncak $hour:00';
  }

  @override
  String get hourlyEmpty => 'Belum ada data per jam';

  @override
  String get histRecent => 'Pencarian terakhir';

  @override
  String get histClear => 'Bersihkan';

  @override
  String get playerMinimize => 'Perkecil';

  @override
  String get playerRepeatOff => 'Ulangi mati';

  @override
  String get playerRepeatAll => 'Ulangi semua';

  @override
  String get playerRepeatOne => 'Ulangi satu';

  @override
  String get queueNotFound => 'Playlist baru tidak ketemu. Coba lagi.';

  @override
  String get abTitle => 'Ulangi A-B';

  @override
  String get abHintInvalid => 'A harus sebelum B dan di dalam lagu';

  @override
  String get abSetA => 'Set A';

  @override
  String get abSetB => 'Set B';

  @override
  String get abClear => 'Bersihkan';

  @override
  String get abDone => 'Selesai';

  @override
  String get abHintSetB => 'A diset, sekarang set B setelah A';

  @override
  String get abHintSetA => 'Set A dulu';

  @override
  String get abHintBAfterA => 'B harus setelah A';

  @override
  String abOn(String a, String b) {
    return 'Ulangi A-B nyala: $a - $b';
  }

  @override
  String get abOff => 'Ulangi A-B mati';

  @override
  String get abButton => 'A-B';

  @override
  String get abTooltip => 'Ulangi A-B';

  @override
  String abMarker(String a, String b) {
    return 'A-B $a - $b';
  }

  @override
  String get bulkEditValidate => 'Isi Genre atau Artist dulu.';

  @override
  String bulkEditSummary(int ok, int failed) {
    return 'Memperbarui $ok lagu, $failed gagal.';
  }

  @override
  String bulkEditTitle(int count) {
    return 'Edit massal ($count lagu)';
  }

  @override
  String get bulkEditHint =>
      'Kosongkan field untuk mempertahankan nilai saat ini.';

  @override
  String get bulkEditGenre => 'Genre';

  @override
  String get bulkEditArtist => 'Artist';

  @override
  String get bulkEditApplying => 'Menerapkan...';

  @override
  String get bulkEditApply => 'Terapkan ke semua';

  @override
  String get bulkEditAction => 'Edit massal';

  @override
  String get dispSection => 'Tampilan';

  @override
  String get dispTextScale => 'Skala teks';

  @override
  String get dispSmall => 'Kecil';

  @override
  String get dispNormal => 'Normal';

  @override
  String get dispLarge => 'Besar';

  @override
  String get dispExtraLarge => 'Sangat besar';

  @override
  String get shortcutShuffle => 'Acak Favorit';

  @override
  String get shortcutContinue => 'Lanjutkan Mendengarkan';

  @override
  String get mergeNoOthers => 'Tidak ada playlist lain untuk digabung.';

  @override
  String get mergeFrom => 'Gabung dari...';

  @override
  String get mergeMenu => 'Gabung...';

  @override
  String mergeSummary(int added, String source, String target, int skipped) {
    return 'Menggabungkan $added lagu dari \"$source\" ke \"$target\" ($skipped sudah ada).';
  }

  @override
  String mergeFailed(String error) {
    return 'Gabung gagal: $error';
  }

  @override
  String get queueClearTitle => 'Bersihkan antrean?';

  @override
  String queueClearMessage(int count) {
    return 'Hapus $count lagu setelah lagu kini? Lagu kini dipertahankan.';
  }

  @override
  String get queueClearAction => 'Bersihkan';

  @override
  String queueCleared(int count) {
    return 'Membersihkan $count lagu dari Antrean';
  }

  @override
  String get queueClearTooltip => 'Bersihkan antrean';

  @override
  String xfDuration(int seconds) {
    return 'Durasi crossfade: $seconds dtk';
  }

  @override
  String get amoledTitle => 'Hitam AMOLED';

  @override
  String get amoledSubtitle => 'Latar hitam pekat untuk tema gelap';

  @override
  String get lyrRefreshed => 'Lirik tersegarkan';

  @override
  String lyrRefreshFailed(String error) {
    return 'Segarkan lirik gagal: $error';
  }

  @override
  String lyrFetchStopped(int done, int total) {
    return 'Berhenti dini: rate limited ($done/$total)';
  }

  @override
  String lyrFetchFinished(int done, int total) {
    return 'Fetch selesai ($done/$total)';
  }

  @override
  String lyrFetchFailed(String error) {
    return 'Fetch lirik gagal: $error';
  }

  @override
  String get lyrMissingTitle => 'Lirik hilang';

  @override
  String get lyrFetchAll => 'Fetch semua';

  @override
  String get lyrAllHave => 'Semua lagu sudah berlirik';

  @override
  String get lyrRefetch => 'Fetch ulang lirik';

  @override
  String get missLyricsEntry => 'Lirik hilang';

  @override
  String get librarySelectAll => 'Pilih semua';

  @override
  String get libraryClearSelection => 'Hapus pilihan';

  @override
  String get libraryJumpPlaying => 'Lompat ke lagu kini';

  @override
  String get playerSpeed => 'Kecepatan';

  @override
  String get playerPitch => 'Nada';

  @override
  String get playerSpeedPitchReset => 'Atur ulang';

  @override
  String get settingsSmartShuffle => 'Acak pintar';

  @override
  String get settingsSmartShuffleSubtitle =>
      'Putar lagu yang jarang diputar dan lama tidak diputar lebih dulu';

  @override
  String get sleepDailySchedule => 'Jadwal harian';

  @override
  String get sleepDailyScheduleSubtitle =>
      'Otomatis mulai sleep timer 30 menit tiap hari';

  @override
  String get sleepDailyScheduleSetTime => 'Atur waktu';

  @override
  String get sleepDailyScheduleHint =>
      'Timer hanya berjalan saat aplikasi terbuka';

  @override
  String get editLyricsSearchOpenFailed => 'Tidak bisa membuka browser';

  @override
  String librarySelectAllTooMany(int limit) {
    return 'Terlalu banyak lagu untuk dipilih semua sekaligus. Pilih maksimal $limit lagu.';
  }

  @override
  String libraryPartialAddedToPlaylist(
      int added, int total, String name, int failed) {
    return 'Menambahkan $added dari $total lagu ke $name, $failed gagal.';
  }

  @override
  String libraryFavoritesAdded(int count) {
    return '$count lagu ditambahkan ke favorit';
  }

  @override
  String get historyCleanupTitle => 'Bersihkan riwayat pendengaran';

  @override
  String get historyCleanupSubtitle =>
      'Hapus riwayat pendengaran lebih dari 12 bulan dan batasi jumlah baris';

  @override
  String get historyCleanupDialogTitle => 'Hapus riwayat lama?';

  @override
  String get historyCleanupMessage =>
      'Riwayat pendengaran lebih dari 12 bulan akan dihapus, dan baris tertua dihapus sampai tersisa maksimal 200.000 baris. Angka dashboard seperti Total listened dan Top songs dihitung dari riwayat ini, jadi angkanya akan turun.';

  @override
  String get historyCleanupAction => 'Hapus';

  @override
  String historyCleanupDone(int count) {
    return 'Menghapus $count baris riwayat';
  }

  @override
  String historyCleanupFailed(String error) {
    return 'Bersihkan riwayat gagal: $error';
  }

  @override
  String get editMetadataRescanRateLimited =>
      'Pengambilan dilewati, terlalu banyak permintaan. Coba lagi sebentar lagi.';

  @override
  String historyPlayFailed(String error) {
    return 'Tidak bisa memutar lagu ini: $error';
  }
}
