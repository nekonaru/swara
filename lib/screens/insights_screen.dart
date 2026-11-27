import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/v6_strings.dart';
import '../models/song.dart';
import '../services/db_helper.dart';
import '../utils/format.dart';

/// Offline listening archive and simple insights from existing history rows.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _totalMs = 0;
  int _streak = 0;
  Map<int, int> _hourly = const {};
  List<Map<String, Object?>> _days = const [];
  List<Song> _recent = const [];

  Future<void> _load() async {
    _totalMs = await DBHelper.instance.getTotalListeningMs();
    _streak = await DBHelper.instance.getListeningStreak();
    _hourly = await DBHelper.instance.getHourlyDistribution();
    _days = await DBHelper.instance.getDailyListeningSeries(30);
    _recent = await DBHelper.instance.getListeningHistoryPage(limit: 50, offset: 0);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _exportCsv() async {
    final buffer = StringBuffer()..writeln('date,minutes');
    for (final row in _days) {
      buffer.writeln('${row['day']},${((row['ms'] as num?)?.toInt() ?? 0) ~/ 60000}');
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}swara_listening.csv');
      await file.writeAsString(buffer.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${V6.csvSaved}: ${file.path}')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final topHour = _hourly.entries.isEmpty
        ? null
        : _hourly.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return Scaffold(
      appBar: AppBar(
        title: Text(V6.listeningArchive),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: V6.exportCsv,
            onPressed: _exportCsv,
          ),
        ],
      ),
      body: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(V6.insights,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(formatDurationLong(_totalMs,
                      indonesian: V6.id)),
                  Text('${V6.id ? 'Rentetan' : 'Streak'}: $_streak'),
                  if (topHour != null)
                    Text('${V6.id ? 'Jam teratas' : 'Top hour'}: ${topHour.key}:00'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final row in _days)
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text('${row['day']}'),
              trailing: Text(
                  '${((row['ms'] as num?)?.toInt() ?? 0) ~/ 60000} m'),
            ),
          const Divider(),
          for (final song in _recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(song.title),
              subtitle: Text(song.artist),
            ),
        ],
      ),
    );
  }
}
