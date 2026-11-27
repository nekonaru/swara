import '../providers/language_provider.dart';

/// Strings for the v5 feature set. Kept in one place so English stays the
/// source and Indonesian is the translation, with no generated-file churn.
class V5 {
  V5._();

  static bool get id => LanguageProvider.instance.isIndonesian;

  static String get label => id ? 'Label' : 'Label';
  static String get setLabel => id ? 'Atur label' : 'Set label';
  static String get labelHint => id ? 'Label opsional' : 'Optional label';
  static String get trash => id ? 'Baru dihapus' : 'Recently removed';
  static String get trashEmpty => id ? 'Tempat sampah kosong' : 'Nothing in trash';
  static String get restore => id ? 'Pulihkan' : 'Restore';
  static String get removeForever =>
      id ? 'Hapus permanen' : 'Delete permanently';
  static String get clearTrash => id ? 'Kosongkan sampah' : 'Empty trash';
  static String get verifyBackup => id ? 'Verifikasi cadangan' : 'Verify backup';
  static String get storageReport =>
      id ? 'Rincian penyimpanan' : 'Storage breakdown';
  static String get searchHistory =>
      id ? 'Pencarian terakhir' : 'Recent searches';
  static String get advancedFilters =>
      id ? 'Filter lanjutan' : 'Advanced filters';
  static String get goal =>
      id ? 'Target mendengarkan harian' : 'Daily listening goal';
  static String get goalMinutes => id ? 'Target menit' : 'Target minutes';
  static String get reports => id ? 'Laporan mendengarkan' : 'Listening report';
  static String get heatmap => id ? 'Peta panas mendengarkan' : 'Listening heatmap';
  static String get diagnostics => id ? 'Diagnostik' : 'Diagnostics';
  static String get diagnosticsEmpty =>
      id ? 'Belum ada masalah tercatat' : 'No issues recorded';
  static String get exportM3u => id ? 'Ekspor M3U' : 'Export M3U';
  static String get relativePaths => id ? 'Jalur relatif' : 'Relative paths';
  static String get customCover => id ? 'Atur sampul khusus' : 'Set custom cover';
  static String get widgetSettings =>
      id ? 'Tata letak widget' : 'Widget layout';
  static String get queueRows => id ? 'Lagu berikutnya' : 'Up-next rows';
  static String get compactWidget => id ? 'Gaya ringkas' : 'Compact style';
  static String get speed => id ? 'Kecepatan pemutaran' : 'Playback speed';
  static String get sessionHistory =>
      id ? 'Diputar sesi ini' : 'Played this session';
  static String get lrcTimeline =>
      id ? 'Editor lirik berwaktu' : 'Timed lyrics editor';
  static String get parseFilename =>
      id ? 'Urai nama file jadi tag' : 'Parse filename to tags';
  static String get autoCollections =>
      id ? 'Koleksi pintar' : 'Smart collections';
  static String get volumeFilter =>
      id ? 'Volume penyimpanan' : 'Storage volume';
  static String get autoBrowseMore =>
      id ? 'Kategori telusur lainnya' : 'More browse categories';
  static String labelApplied(int count) => id
      ? 'Label diterapkan ke $count lagu'
      : 'Label applied to $count songs';
  static String get goalSaved => id ? 'Target tersimpan' : 'Goal saved';
  static String get noGoal => id ? 'Belum ada target' : 'No goal set';
  static String parsedPreview(String artist, String title) =>
      id ? 'Pratinjau: $artist - $title' : 'Preview: $artist - $title';
  static String get applyParsed =>
      id ? 'Terapkan tag hasil urai' : 'Apply parsed tags';
  static String get m3uSaved => id ? 'M3U tersimpan' : 'M3U saved';
  static String get restartForWidget => id
      ? 'Mulai ulang aplikasi untuk menerapkan tata letak widget'
      : 'Restart the app to apply widget layout';
  static String trashConfirm(String name) => id
      ? 'Pindahkan "$name" ke tempat sampah? Bisa dipulihkan nanti.'
      : 'Move "$name" to trash? It can be restored later.';
  static String restoreConfirm(String name) =>
      id ? 'Pulihkan "$name" ke pustaka?' : 'Restore "$name" to the library?';
  static String permanentConfirm(String name) => id
      ? 'Hapus "$name" dari sampah secara permanen? Tidak bisa dibatalkan.'
      : 'Delete "$name" from trash permanently? This cannot be undone.';
  static String get clearTrashConfirm => id
      ? 'Kosongkan sampah? Semua entri akan dihapus permanen.'
      : 'Empty the trash? All entries will be removed permanently.';
  static String verifyResult(int songs, int playlists, int lyrics) => id
      ? 'Ditemukan dalam cadangan: $songs lagu, $playlists playlist, $lyrics lirik'
      : 'Found in backup: $songs songs, $playlists playlists, $lyrics lyrics';
  static String day(int d) => id
      ? const ['', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'][d]
      : const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d];
  static String minutesToday(int minutes) =>
      id ? '$minutes menit hari ini' : '$minutes minutes today';
  static String get clearHistory => id ? 'Hapus riwayat' : 'Clear history';
  static String get moreTools => id ? 'Alat tambahan' : 'More tools';
  static String get share => id ? 'Bagikan' : 'Share';
  static String get all => id ? 'Semua' : 'All';
  static String get newSongs => id ? 'Lagu baru' : 'New songs';
  static String get unplayed => id ? 'Belum diputar' : 'Unplayed';
  static String get genres => id ? 'Genre' : 'Genres';
  static String get markPlayed => id ? 'Tandai diputar' : 'Mark played';
  static String get coverSaved => id ? 'Sampul disimpan' : 'Cover saved';
  static String get more => id ? 'Lainnya' : 'More';
  static String get internalStorage => id ? 'Internal' : 'Internal';
  static String get sdCard => id ? 'Kartu SD' : 'SD card';
  static String get historyEmpty =>
      id ? 'Belum ada lagu diputar sesi ini' : 'No songs played this session';
  static String get backupTooNew => id
      ? 'Cadangan dari versi lebih baru tidak didukung'
      : 'Backup from a newer version is not supported';
}
