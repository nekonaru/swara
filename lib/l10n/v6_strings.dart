import '../providers/language_provider.dart';

/// Strings for the v6 feature set. English is the source, Indonesian the
/// translation, selected from the same locale the rest of the app uses.
class V6 {
  V6._();

  static bool get id => LanguageProvider.instance.isIndonesian;

  static String get rate => id ? 'Beri rating' : 'Rate';
  static String get rating => id ? 'Rating' : 'Rating';
  static String get clearRating => id ? 'Hapus rating' : 'Clear rating';
  static String get manageLabels => id ? 'Kelola label' : 'Manage labels';
  static String get renameLabel => id ? 'Ganti nama label' : 'Rename label';
  static String get mergeLabel => id ? 'Gabungkan label' : 'Merge label';
  static String get mergeInto => id ? 'Gabungkan ke' : 'Merge into';
  static String get removeLabel => id ? 'Hapus label' : 'Remove label';
  static String get labelName => id ? 'Nama label' : 'Label name';
  static String get playlistFolders =>
      id ? 'Folder playlist' : 'Playlist folders';
  static String get moveToFolder =>
      id ? 'Pindah ke folder' : 'Move to folder';
  static String get newFolder => id ? 'Folder baru' : 'New folder';
  static String get noFolder => id ? 'Tanpa folder' : 'No folder';
  static String get artists => id ? 'Artis' : 'Artists';
  static String get genres => id ? 'Genre' : 'Genres';
  static String get similarSongs => id ? 'Lagu serupa' : 'Similar songs';
  static String get listeningArchive =>
      id ? 'Arsip mendengarkan' : 'Listening archive';
  static String get insights => id ? 'Wawasan' : 'Insights';
  static String get exportCsv => id ? 'Ekspor CSV' : 'Export CSV';
  static String get autoDj => id ? 'Auto DJ' : 'Auto DJ';
  static String get djPreview => id ? 'Pratinjau antrean' : 'Queue preview';
  static String get djApply => id ? 'Gunakan antrean ini' : 'Use this queue';
  static String get shuffleFair =>
      id ? 'Acakan adil' : 'Fair shuffle';
  static String get shuffleFairHint => id
      ? 'Artis yang sama tidak berdekatan'
      : 'Avoid repeating an artist back to back';
  static String get playModes => id ? 'Mode putar' : 'Play modes';
  static String get playNewest => id ? 'Terbaru dulu' : 'Newest first';
  static String get playLeast => id ? 'Paling jarang' : 'Least played';
  static String get playUnplayed => id ? 'Belum diputar' : 'Unplayed only';
  static String get sleepAlbum =>
      id ? 'Sampai album habis' : 'Until album ends';
  static String get lyricsSync => id ? 'Sinkronkan baris ini' : 'Sync this line';
  static String get metadataInbox =>
      id ? 'Metadata gagal' : 'Failed metadata';
  static String get tagPreview =>
      id ? 'Pratinjau perubahan tag' : 'Tag change preview';
  static String get restorePreview =>
      id ? 'Pratinjau pemulihan' : 'Restore preview';
  static String get incrementalBackup =>
      id ? 'Cadangan inkremental' : 'Incremental backup';
  static String get freeSpace =>
      id ? 'Saran ruang' : 'Free up space';
  static String get browseRating => id ? 'Berdasarkan rating' : 'By rating';
  static String get browseLabel => id ? 'Berdasarkan label' : 'By label';
  static String get browseHistory =>
      id ? 'Riwayat per tanggal' : 'History by date';
  static String get notificationStyle =>
      id ? 'Gaya notifikasi' : 'Notification style';
  static String get notificationsCompact =>
      id ? 'Ringkas' : 'Compact';
  static String get notificationsFull => id ? 'Penuh' : 'Full';
  static String songsCount(int n) => id ? '$n lagu' : '$n songs';
  static String get noItems => id ? 'Tidak ada entri' : 'No entries';
  static String labelsMerged(int n) =>
      id ? '$n label digabungkan' : '$n labels merged';
  static String ratingSet(int n) =>
      id ? 'Rating $n bintang' : '$n star rating';
  static String djReady(int n) =>
      id ? '$n lagu disiapkan' : '$n songs prepared';
  static String get csvSaved => id ? 'CSV tersimpan' : 'CSV saved';
  static String get csvFailed => id ? 'Gagal mengekspor CSV' : 'CSV export failed';
  static String get folderCreated => id ? 'Folder dibuat' : 'Folder created';
  static String ratePrompt(int n) =>
      id ? 'Beri rating $n bintang?' : 'Rate $n stars?';
}
