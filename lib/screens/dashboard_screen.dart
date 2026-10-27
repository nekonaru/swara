import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/db_helper.dart';
import '../models/song.dart';
import '../services/player_service.dart';
import '../utils/format.dart';

class DashboardScreen extends StatefulWidget {
  // When false, the screen skips the automatic load in initState so the
  // parent can defer the first load until the tab is actually opened.
  // Defaults to true to keep standalone uses unchanged.
  final bool autoLoad;
  const DashboardScreen({super.key, this.autoLoad = true});
  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  Map<DateTime, int> _daily = {};
  List<MapEntry<int, int>> _topSongIds = [];
  List<MapEntry<String, int>> _topArtists = [];
  Map<String, int> _genreDist = {};
  Map<int, Song> _songLookup = {};
  int _totalSongs = 0;
  int _totalListeningMs = 0;
  int _thisMonthMs = 0;
  int _yearMs = 0;
  List<MapEntry<int, int>> _yearTopSongs = [];
  List<MapEntry<String, int>> _yearTopArtists = [];
  int _streak = 0;
  String? _topGenreMonth;
  Map<int, int> _hourly = {for (int h = 0; h < 24; h++) h: 0};
  bool _fromCache = false;
  List<Song> _neverPlayed = [];
  bool _loading = true;
  String? _error;

  // Key for capturing the Yearly Recap card as an image.
  final GlobalKey _recapKey = GlobalKey();

  // Aggregate cache for the dashboard summary numbers, with a 10 minute TTL.
  static const _aggregateCacheKey = 'dashboard_aggregate_cache_v1';
  static const _aggregateCacheTtl = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    // Lazy gate for startup: HomeScreen builds this screen inside an
    // IndexedStack with autoLoad false, so no DB work runs until
    // ensureLoaded is called on the first tab open.
    if (widget.autoLoad) {
      _loaded = true;
      _load();
    }
  }

  // First load entry point for lazy parents (HomeScreen). Runs the normal
  // load exactly once; later calls are no-ops. Use reload() for refresh.
  bool _loaded = false;
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    _loaded = true;
    return _load();
  }

  // Called on every tab switch, so it always recomputes and rewrites the
  // cache. A newly recorded listening entry can never leave stale numbers
  // behind on the next dashboard visit.
  Future<void> reload() {
    _loaded = true;
    return _load(forceRefresh: true);
  }

  /// Cached summary map, or null when absent, expired, or malformed.
  /// Never throws: any problem means the caller recomputes instead.
  Future<Map<String, dynamic>?> _readAggregateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_aggregateCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cacheTime = DateTime.tryParse('${map['cacheTime']}');
      if (cacheTime == null) return null;
      if (DateTime.now().difference(cacheTime) >= _aggregateCacheTtl) {
        return null;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  /// Persist the summary numbers. Best effort only, never fails the load.
  Future<void> _writeAggregateCache({
    required int totalSongs,
    required int totalMs,
    required int monthMs,
    required int streak,
    required String? topGenre,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _aggregateCacheKey,
        jsonEncode({
          'totalSongs': totalSongs,
          'totalMs': totalMs,
          'monthMs': monthMs,
          'streak': streak,
          'topGenre': topGenre,
          'cacheTime': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {
      // Cache is optional, ignore write failures.
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Only the summary numbers come from the cache. Detail lists are
      // always read fresh from the DB. When in doubt, recompute instead
      // of showing data that might be stale.
      final cached = forceRefresh ? null : await _readAggregateCache();
      final useCache = cached != null;

      // Detail queries always run fresh so lists never go stale.
      // Query order is fixed: details, then optional summary, then hourly.
      final nowForYear = DateTime.now();
      final yearStart =
          DateTime(nowForYear.year, 1, 1).toIso8601String();
      // Named futures via a record, spread in order so indices never shift.
      final (detailFutures, summaryFutures, hourlyFuture) = (
        <Future>[
          DBHelper.instance.getDailyListeningLast7Days(),
          DBHelper.instance.getTopSongIds(limit: 5),
          DBHelper.instance.getTopArtists(limit: 5),
          DBHelper.instance.getGenreDistribution(),
          DBHelper.instance.getAllSongs(),
          DBHelper.instance.getNeverPlayedSongs(),
          DBHelper.instance.getTopSongIdsSince(yearStart, limit: 5),
          DBHelper.instance.getTopArtistsSince(yearStart, limit: 3),
          DBHelper.instance.getListeningMsSince(yearStart),
        ],
        // Summary queries only run on a cache miss or forced refresh.
        useCache
            ? <Future>[]
            : <Future>[
                DBHelper.instance.getTotalListeningMs(),
                DBHelper.instance.getThisMonthListeningMs(),
                DBHelper.instance.getListeningStreak(),
                DBHelper.instance.getTopGenreThisMonth(),
              ],
        // Hourly distribution always runs fresh with the detail queries.
        // Appended last so the summary indices above never shift.
        DBHelper.instance.getHourlyDistribution(),
      );
      final futures = <Future>[
        ...detailFutures,
        ...summaryFutures,
        hourlyFuture,
      ];

      final results = await Future.wait(futures);
      final daily = results[0] as Map<DateTime, int>;
      final rawTopSongs = results[1] as List<MapEntry<int, int>>;
      final topArtists = results[2] as List<MapEntry<String, int>>;
      final genreDist = results[3] as Map<String, int>;
      final dbSongs = results[4] as List<Song>;
      final neverPlayedFromDb = results[5] as List<Song>;
      final rawYearTopSongs = results[6] as List<MapEntry<int, int>>;
      final yearTopArtists = results[7] as List<MapEntry<String, int>>;
      final yearMs = results[8] as int;
      // Hidden folders must not show up in the dashboard either. The DB has
      // no idea they are hidden, so apply the same rule the library uses.
      // Otherwise the dashboard counts more songs than the library shows, and
      // "play all" would start songs the user deliberately hid.
      final excluded = await DBHelper.instance.getExcludedFolders();
      bool visible(Song s) =>
          excluded.isEmpty || !excluded.contains(folderOf(s.filePath));
      final allSongs =
          excluded.isEmpty ? dbSongs : dbSongs.where(visible).toList();
      final neverPlayed = excluded.isEmpty
          ? neverPlayedFromDb
          : neverPlayedFromDb.where(visible).toList();
      final hiddenIds = <int>{
        for (final s in dbSongs)
          if (!visible(s)) s.id,
      };
      // Top songs are keyed by song id so hidden ones can be dropped. The
      // genre chart is a per genre aggregate with no song key, so it is left
      // alone rather than guessing which genres belong only to hidden songs.
      final topSongs = hiddenIds.isEmpty
          ? rawTopSongs
          : rawTopSongs.where((e) => !hiddenIds.contains(e.key)).toList();
      final yearTopSongs = hiddenIds.isEmpty
          ? rawYearTopSongs
          : rawYearTopSongs.where((e) => !hiddenIds.contains(e.key)).toList();
      // Named offsets into the conditional summary block.
      final summaryStart = detailFutures.length;
      final totalMsIndex = summaryStart;
      final monthMsIndex = summaryStart + 1;
      final streakIndex = summaryStart + 2;
      final topGenreIndex = summaryStart + 3;
      // Hourly map is always the last future in the list.
      final hourlyIndex = summaryStart + summaryFutures.length;
      final hourly = results[hourlyIndex] as Map<int, int>;

      final int totalMs;
      final int monthMs;
      final int streak;
      final String? topGenre;
      if (useCache) {
        totalMs = (cached['totalMs'] as num?)?.toInt() ?? 0;
        monthMs = (cached['monthMs'] as num?)?.toInt() ?? 0;
        streak = (cached['streak'] as num?)?.toInt() ?? 0;
        final rawGenre = cached['topGenre'];
        topGenre = rawGenre is String && rawGenre.isNotEmpty ? rawGenre : null;
      } else {
        totalMs = results[totalMsIndex] as int;
        monthMs = results[monthMsIndex] as int;
        streak = results[streakIndex] as int;
        topGenre = results[topGenreIndex] as String?;
        await _writeAggregateCache(
          totalSongs: allSongs.length,
          totalMs: totalMs,
          monthMs: monthMs,
          streak: streak,
          topGenre: topGenre,
        );
      }

      if (!mounted) return;
      setState(() {
        _daily = daily;
        _topSongIds = topSongs;
        _topArtists = topArtists;
        _genreDist = genreDist;
        _songLookup = {for (final s in allSongs) s.id: s};
        _totalSongs = allSongs.length;
        _totalListeningMs = totalMs;
        _thisMonthMs = monthMs;
        _yearMs = yearMs;
        _yearTopSongs = yearTopSongs;
        _yearTopArtists = yearTopArtists;
        _streak = streak;
        _topGenreMonth = topGenre;
        _hourly = hourly;
        _neverPlayed = neverPlayed;
        _fromCache = useCache;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;

  // Capture the Yearly Recap card and share it as a PNG image.
  Future<void> _shareRecapAsImage() async {
    try {
      final object = _recapKey.currentContext?.findRenderObject();
      if (object == null || object is! RenderRepaintBoundary) return;
      final image = await object.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/yearly_recap.png');
      await file.writeAsBytes(
          byteData.buffer.asUint8List(
              byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: l10n.recapShareText),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .recapShareFailed(e.toString()))),
      );
    }
  }

  bool get _hasAnyData =>
      _daily.values.any((ms) => ms > 0) || _topSongIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_loading) {
      return const _DashboardSkeleton();
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 20),
              Text(
                l.dashboardLoadFailedTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[500]),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(l.dashboardRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasAnyData) {
      return RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.bar_chart_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 20),
            Text(
              l.dashboardEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              l.dashboardEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            // Basic summary even without history yet
            _StatCard(
              icon: Icons.library_music_outlined,
              value: '$_totalSongs',
              label: l.dashboardTotalSongsLibrary,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      );
    }

    final totalHours = _totalListeningMs / 3600000;
    final monthHours = _thisMonthMs / 3600000;
    final weekMs = _daily.values.fold<int>(0, (a, b) => a + b);
    final weekHours = weekMs / 3600000;

    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Statistik ringkasan
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.library_music_outlined,
                  value: '$_totalSongs',
                  label: l.dashboardTotalSongs,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.headphones_outlined,
                  value: l.dashboardHoursValue(totalHours.toStringAsFixed(0)),
                  label: l.dashboardTotalListened,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.today_outlined,
                  value: l.dashboardHoursValue(monthHours.toStringAsFixed(1)),
                  label: l.dashboardThisMonth,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Streak and top genre this month.
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.local_fire_department_outlined,
                  value: '$_streak',
                  label: AppLocalizations.of(context)!.dashStreak,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.category_outlined,
                  value: _topGenreMonth ?? '-',
                  label:
                      AppLocalizations.of(context)!.dashTopGenreMonth,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          // Small badge shown when the summary numbers come from the cache.
          if (_fromCache)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(AppLocalizations.of(context)!.dashCached,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ),
          const SizedBox(height: 16),

          // 7-day chart
          _SectionCard(
            icon: Icons.show_chart,
            title: l.dashboardListeningWeekTitle,
            trailing: Text(l.dashboardWeekTotal(weekHours.toStringAsFixed(1)),
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            child: SizedBox(height: 160, child: _buildBarChart()),
          ),
          const SizedBox(height: 14),

          // Top 5 songs (interactive)
          if (_topSongIds.isNotEmpty)
            _SectionCard(
              icon: Icons.music_note_outlined,
              title: l.dashboardTopSongs,
              child: Column(
                children: [
                  for (int i = 0; i < _topSongIds.length; i++) ...[
                    _RankTile(
                      rank: i + 1,
                      title: _songLookup[_topSongIds[i].key]?.title ??
                          l.dashboardUnknownSong(_topSongIds[i].key),
                      subtitle: _songLookup[_topSongIds[i].key]?.artist,
                      trailing: l.dashboardPlayCount(_topSongIds[i].value),
                      maxValue: _topSongIds.first.value,
                      value: _topSongIds[i].value,
                      onTap: () async {
                        final song = _songLookup[_topSongIds[i].key];
                        if (song != null) {
                          try {
                            await PlayerService.instance
                                .setQueueAndPlay([song], 0);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 5),
                                    content: Text(l.dashboardPlayFailed(e.toString()))),
                              );
                            }
                          }
                        }
                      },
                    ),
                    if (i < _topSongIds.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          if (_topSongIds.isNotEmpty) const SizedBox(height: 14),

          // Top artists (interactive)
          if (_topArtists.isNotEmpty)
            _SectionCard(
              icon: Icons.person_outline,
              title: l.dashboardTopArtists,
              child: Column(
                children: [
                  for (int i = 0; i < _topArtists.length; i++) ...[
                    _RankTile(
                      rank: i + 1,
                      title: _topArtists[i].key,
                      trailing: l.dashboardPlayCount(_topArtists[i].value),
                      maxValue: _topArtists.first.value,
                      value: _topArtists[i].value,
                    ),
                    if (i < _topArtists.length - 1) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          if (_topArtists.isNotEmpty) const SizedBox(height: 14),

          // Yearly recap: top songs and artists plus total hours this year.
          // Wrapped in RepaintBoundary so it can be shared as an image.
          if (_yearMs > 0 ||
              _yearTopSongs.isNotEmpty ||
              _yearTopArtists.isNotEmpty)
            RepaintBoundary(
              key: _recapKey,
              child: _SectionCard(
                icon: Icons.celebration_outlined,
                title: l.recapTitle,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        l.dashboardHoursValue(
                            (_yearMs / 3600000).toStringAsFixed(1)),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                    // Share button captures the card above as a PNG image.
                    IconButton(
                      onPressed: _shareRecapAsImage,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      tooltip: l.recapShareTooltip,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0;
                      i < _yearTopSongs.length && i < 5;
                      i++) ...[
                    _RankTile(
                      rank: i + 1,
                      title: _songLookup[_yearTopSongs[i].key]?.title ??
                          l.dashboardUnknownSong(_yearTopSongs[i].key),
                      subtitle:
                          _songLookup[_yearTopSongs[i].key]?.artist,
                      trailing:
                          l.dashboardPlayCount(_yearTopSongs[i].value),
                      maxValue: _yearTopSongs.first.value,
                      value: _yearTopSongs[i].value,
                      onTap: () async {
                        final song =
                            _songLookup[_yearTopSongs[i].key];
                        if (song != null) {
                          try {
                            await PlayerService.instance
                                .setQueueAndPlay([song], 0);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                    behavior:
                                        SnackBarBehavior.floating,
                                    duration:
                                        const Duration(seconds: 5),
                                    content: Text(l.dashboardPlayFailed(
                                        e.toString()))),
                              );
                            }
                          }
                        }
                      },
                    ),
                    if (i < _yearTopSongs.length - 1 &&
                        i < 4)
                      const Divider(height: 1),
                  ],
                  if (_yearTopArtists.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(l.recapTopArtists,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    for (int i = 0;
                        i < _yearTopArtists.length && i < 3;
                        i++) ...[
                      _RankTile(
                        rank: i + 1,
                        title: _yearTopArtists[i].key,
                        trailing: l
                            .dashboardPlayCount(_yearTopArtists[i].value),
                        maxValue: _yearTopArtists.first.value,
                        value: _yearTopArtists[i].value,
                      ),
                      if (i < _yearTopArtists.length - 1 && i < 2)
                        const Divider(height: 1),
                    ],
                  ],
                ],
              ),
              ),
            ),
          if (_yearMs > 0 ||
              _yearTopSongs.isNotEmpty ||
              _yearTopArtists.isNotEmpty)
            const SizedBox(height: 14),

          // Genre distribution
          if (_genreDist.isNotEmpty)
            _SectionCard(
              icon: Icons.category_outlined,
              title: l.dashboardGenreTitle,
              trailing: Text(l.dashboardGenreCount(_genreDist.length),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              child: _buildGenreList(),
            ),
          if (_genreDist.isNotEmpty) const SizedBox(height: 14),

          // Never played
          if (_neverPlayed.isNotEmpty)
            _SectionCard(
              icon: Icons.not_interested_outlined,
              title: l.dashboardNeverPlayedTitle,
              trailing: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showNeverPlayed(),
                child: Container(
                  alignment: Alignment.centerRight,
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Text(l.dashboardSongCount(_neverPlayed.length),
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: [
                    Text(
                      l.dashboardNeverPlayedSubtitle(_neverPlayed.length),
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showNeverPlayed,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: Text(l.dashboardPlayAll),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_neverPlayed.isNotEmpty) const SizedBox(height: 14),

          // Streak info
          _SectionCard(
            icon: Icons.local_fire_department_outlined,
            title: l.dashboardWeekActivityTitle,
            child: _buildWeekActivity(),
          ),
          const SizedBox(height: 14),

          // Hourly listening pattern across the 24 hours of the day.
          _SectionCard(
            icon: Icons.schedule_outlined,
            title: l.hourlyTitle,
            trailing: _hourlyPeakLabel(),
            child: _buildHourlyChart(),
          ),
        ],
      ),
    );
  }

  /// Peak hour label like "Peak 20:00", or null when there is no data.
  Widget? _hourlyPeakLabel() {
    var peakHour = -1;
    var peakMs = 0;
    _hourly.forEach((hour, ms) {
      if (ms > peakMs) {
        peakMs = ms;
        peakHour = hour;
      }
    });
    if (peakHour < 0) return null;
    return Text(
        AppLocalizations.of(context)!.hourlyPeak(
            peakHour.toString().padLeft(2, '0')),
        style: TextStyle(fontSize: 12, color: Colors.grey[500]));
  }

  /// 24 vertical bars for total listened time per hour of day.
  Widget _buildHourlyChart() {
    final values =
        List<double>.generate(24, (h) => (_hourly[h] ?? 0) / 3600000);
    final hasData = values.any((v) => v > 0);
    if (!hasData) {
      return Text(AppLocalizations.of(context)!.hourlyEmpty);
    }
    final cs = Theme.of(context).colorScheme;
    // Peak bar uses the tertiary color, the rest use primary.
    var peakIndex = 0;
    for (int i = 1; i < values.length; i++) {
      if (values[i] > values[peakIndex]) peakIndex = i;
    }
    return Column(
      children: [
        SizedBox(
          height: 140,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _HourlyBarsPainter(
                values: values,
                barColor: cs.primary,
                peakBarColor: cs.tertiary,
                gridColor: cs.outlineVariant.withValues(alpha: 0.4),
                peakIndex: peakIndex,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int h = 0; h < 24; h++)
              Expanded(
                child: Text(
                  // Label every 6 hours to avoid crowding, others blank.
                  h % 6 == 0
                      ? AppLocalizations.of(context)!
                          .dashboardTooltipHours(h.toString())
                      : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: h == peakIndex
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: h == peakIndex ? cs.primary : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenreList() {
    final entries = _genreDist.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty ? 1 : entries.first.value;
    final topGenres = entries.take(6).toList();
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        RepaintBoundary(
          child: SizedBox(
            height: 128,
            child: Row(
              children: [
                CustomPaint(
                  size: const Size(116, 116),
                  painter: _GenreDonutPainter(
                    values:
                        topGenres.map((e) => e.value.toDouble()).toList(),
                    colors: List.generate(topGenres.length,
                        (i) => _chartColor(cs, i)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < topGenres.length; i++)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _chartColor(cs, i),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(topGenres[i].key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 6),
                              Text('${topGenres[i].value}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500])),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...topGenres.map((e) {
        final ratio = (e.value / max).clamp(0.04, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(e.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 6,
                  child: CustomPaint(
                    painter: _HBarPainter(
                      ratio: ratio,
                      barColor:
                          Theme.of(context).colorScheme.primary,
                      trackColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        );
        }),
      ],
    );
  }

  Widget _buildWeekActivity() {
    final l = AppLocalizations.of(context)!;
    final days = _daily.keys.toList()..sort();
    final dayNames = [l.dashboardDaySun, l.dashboardDayMon, l.dashboardDayTue, l.dashboardDayWed, l.dashboardDayThu, l.dashboardDayFri, l.dashboardDaySat];
    if (days.isEmpty) return Text(l.dashboardNoWeekActivity);
    final now = DateTime.now();
    final activeDays = days.where((d) => (_daily[d] ?? 0) > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.dashboardActiveDays(activeDays),
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: days.map((d) {
            final ms = _daily[d] ?? 0;
            final isToday = _isSameDay(d, now);
            final hasData = ms > 0;
            return Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hasData
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                    border: isToday
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2)
                        : null,
                  ),
                  child: Center(
                    child: hasData
                        ? Icon(Icons.headphones,
                            size: 14,
                            color: Theme.of(context).colorScheme.onPrimary)
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(dayNames[d.weekday % 7],
                    style: TextStyle(
                        fontSize: 10,
                        color: isToday
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500])),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showNeverPlayed() {
    if (_neverPlayed.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.not_interested_outlined),
                  const SizedBox(width: 8),
                  Text(l.dashboardNeverPlayedSheetTitle(_neverPlayed.length),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await PlayerService.instance
                            .setQueueAndPlay(_neverPlayed, 0);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 5),
                                content: Text(
                                    l.dashboardPlayFailed(e.toString()))),
                          );
                        }
                      }
                    },
                    child: Text(l.dashboardPlayAll),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _neverPlayed.length,
                itemExtent: 64,
                itemBuilder: (context, i) {
                  final s = _neverPlayed[i];
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(formatDuration(s.durationMs),
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await PlayerService.instance
                            .setQueueAndPlay(_neverPlayed, i);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 5),
                                content: Text(
                                    l.dashboardPlayFailed(e.toString()))),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    final l = AppLocalizations.of(context)!;
    final days = _daily.keys.toList()..sort();
    final now = DateTime.now();
    if (days.isEmpty) {
      return Center(child: Text(l.dashboardNoWeekActivity));
    }
    final values = days.map((d) => (_daily[d] ?? 0) / 3600000).toList();
    final dayLabels = [
      l.dashboardDaySun,
      l.dashboardDayMon,
      l.dashboardDayTue,
      l.dashboardDayWed,
      l.dashboardDayThu,
      l.dashboardDayFri,
      l.dashboardDaySat
    ];
    final names = days.map((d) => dayLabels[d.weekday % 7]).toList();
    final cs = Theme.of(context).colorScheme;
    final todayIndex = days.indexWhere((d) => _isSameDay(d, now));
    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _WeekBarsPainter(
                values: values,
                barColor: cs.primary,
                todayBarColor: cs.tertiary,
                gridColor: cs.outlineVariant.withValues(alpha: 0.4),
                todayIndex: todayIndex,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (int i = 0; i < names.length; i++)
              Expanded(
                child: Text(
                  names[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == todayIndex
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: i == todayIndex ? cs.primary : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// First load skeleton: grey pulsing boxes, no new dependency.
// ─────────────────────────────────────────────────────────────

/// Single grey bar that fades in once on first load.
class _SkeletonBar extends StatelessWidget {
  final double height;
  const _SkeletonBar({required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.35, end: 0.7),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, v, _) => Opacity(
        opacity: v,
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Simple skeleton for the dashboard first load.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        Row(
          children: [
            Expanded(child: _SkeletonBar(height: 92)),
            SizedBox(width: 10),
            Expanded(child: _SkeletonBar(height: 92)),
            SizedBox(width: 10),
            Expanded(child: _SkeletonBar(height: 92)),
          ],
        ),
        SizedBox(height: 16),
        _SkeletonBar(height: 190),
        SizedBox(height: 14),
        _SkeletonBar(height: 150),
        SizedBox(height: 14),
        _SkeletonBar(height: 120),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _StatCard({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  const _SectionCard(
      {required this.icon,
      required this.title,
      required this.child,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  final int? rank;
  final String title;
  final String? subtitle;
  final String trailing;
  final int value;
  final int maxValue;
  final VoidCallback? onTap;
  const _RankTile({
    this.rank,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.value,
    required this.maxValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final ratio = maxValue > 0 ? (value / maxValue).clamp(0.03, 1.0) : 0.03;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (rank != null) ...[
              SizedBox(
                width: 22,
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 13,
                        color: rank! <= 3 ? color : Colors.grey[500],
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      Text(trailing,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      if (onTap != null) const SizedBox(width: 4),
                      if (onTap != null)
                        Icon(Icons.play_circle_outline,
                            size: 16, color: Colors.grey[400]),
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 3,
                      child: CustomPaint(
                        painter: _HBarPainter(
                          ratio: ratio.toDouble(),
                          barColor: color,
                          trackColor: color.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Theme aware palette for the custom painted charts.
Color _chartColor(ColorScheme cs, int index) {
  const palette = <Color>[
    Colors.blue,
    Colors.purple,
    Colors.teal,
    Colors.orange,
    Colors.pink,
    Colors.green,
  ];
  if (index == 0) return cs.primary;
  if (index == 1) return cs.secondary;
  if (index == 2) return cs.tertiary;
  return palette[index % palette.length];
}

/// Vertical 7 day bars with grid lines, painted without any chart package.
class _WeekBarsPainter extends CustomPainter {
  final List<double> values;
  final Color barColor;
  final Color todayBarColor;
  final Color gridColor;
  final int todayIndex;
  const _WeekBarsPainter({
    required this.values,
    required this.barColor,
    required this.todayBarColor,
    required this.gridColor,
    required this.todayIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int g = 1; g <= 3; g++) {
      final y = size.height - (size.height * g / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;
    const gap = 8.0;
    final n = values.length;
    final barW = (size.width - gap * (n - 1)) / n;
    for (int i = 0; i < n; i++) {
      final h = (values[i] / safeMax * (size.height - 12)).clamp(4.0, size.height);
      final x = i * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barW.clamp(8.0, 48.0), h),
        const Radius.circular(6),
      );
      canvas.drawRRect(
          rect, Paint()..color = i == todayIndex ? todayBarColor : barColor);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekBarsPainter old) =>
      old.values != values ||
      old.todayIndex != todayIndex ||
      old.barColor != barColor;
}

/// Vertical 24 hour bars with grid lines, painted without any chart package.
/// Same style as [_WeekBarsPainter], with a highlighted peak bar.
class _HourlyBarsPainter extends CustomPainter {
  final List<double> values;
  final Color barColor;
  final Color peakBarColor;
  final Color gridColor;
  final int peakIndex;
  const _HourlyBarsPainter({
    required this.values,
    required this.barColor,
    required this.peakBarColor,
    required this.gridColor,
    required this.peakIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (int g = 1; g <= 3; g++) {
      final y = size.height - (size.height * g / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;
    const gap = 3.0;
    final n = values.length;
    final barW = (size.width - gap * (n - 1)) / n;
    for (int i = 0; i < n; i++) {
      final h = (values[i] / safeMax * (size.height - 12)).clamp(4.0, size.height);
      final x = i * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barW, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(
          rect, Paint()..color = i == peakIndex ? peakBarColor : barColor);
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyBarsPainter old) =>
      old.values != values ||
      old.peakIndex != peakIndex ||
      old.barColor != barColor;
}

/// Horizontal progress bar with rounded ends, theme aware.
class _HBarPainter extends CustomPainter {
  final double ratio;
  final Color barColor;
  final Color trackColor;
  const _HBarPainter({
    required this.ratio,
    required this.barColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = ratio.clamp(0.0, 1.0);
    final track = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(track, Paint()..color = trackColor);
    if (r <= 0) return;
    final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * r, size.height),
        Radius.circular(size.height / 2));
    canvas.drawRRect(fill, Paint()..color = barColor);
  }

  @override
  bool shouldRepaint(covariant _HBarPainter old) =>
      old.ratio != ratio ||
      old.barColor != barColor ||
      old.trackColor != trackColor;
}

/// Simple donut chart for the top genres, painted without any package.
class _GenreDonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _GenreDonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 22;
    if (total <= 0) {
      paint.color = const Color(0xFFE0E0E0);
      canvas.drawCircle(center, radius - 11, paint);
      return;
    }
    var start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      paint.color = colors[i % colors.length];
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 11),
          start,
          sweep < 0.02 && values[i] > 0 ? 0.02 : sweep,
          false,
          paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _GenreDonutPainter old) =>
      old.values != values || old.colors != colors;
}
