import 'dart:async';
import 'dart:isolate';

import '../utils/search_filter.dart';

typedef SearchIsolateResult = ({List<int> indices, String? suggestion});

/// One long-lived search isolate. The haystack lists are prepared once per
/// library version and filter, then keystrokes send only the query text.
void searchIsolateEntry(SendPort replyPort) {
  final commands = ReceivePort();
  final cache = <String, ({
    List<String> haystacks,
    List<String> suggestHaystacks,
  })>{};
  String? currentKey;
  replyPort.send({'type': 'ready', 'port': commands.sendPort});
  commands.listen((message) {
    if (message is! Map<String, dynamic>) return;
    switch (message['type']) {
      case 'prepare':
        final key = message['key'] as String?;
        if (key == null) return;
        if (currentKey != null && currentKey != key) cache.remove(currentKey);
        currentKey = key;
        cache[key] = (
          haystacks: (message['haystacks'] as List? ?? const []).cast<String>(),
          suggestHaystacks:
              (message['suggestHaystacks'] as List? ?? const []).cast<String>(),
        );
        break;
      case 'query':
        final key = message['key'] as String?;
        final generation = (message['generation'] as num?)?.toInt() ?? -1;
        if (key == null) {
          replyPort.send({
            'type': 'error',
            'generation': generation,
            'message': 'Missing search key',
          });
          return;
        }
        final entry = cache[key];
        if (entry == null) {
          replyPort.send({
            'type': 'result',
            'generation': generation,
            'indices': const <int>[],
            'suggestion': null,
          });
          return;
        }
        try {
          final result = filterSongsIsolate(<String, dynamic>{
            'haystacks': entry.haystacks,
            'suggestHaystacks': entry.suggestHaystacks,
            'query': message['query'] ?? '',
            'limit': message['limit'] ?? 500,
          });
          replyPort.send({
            'type': 'result',
            'generation': generation,
            'indices': result['indices'] ?? const <int>[],
            'suggestion': result['suggestion'],
          });
        } catch (e) {
          replyPort.send({
            'type': 'error',
            'generation': generation,
            'message': e.toString(),
          });
        }
        break;
      case 'evict':
        final key = message['key'] as String?;
        if (key != null) cache.remove(key);
        break;
      case 'close':
        commands.close();
        Isolate.current.kill();
        break;
    }
  });
}

class SearchIsolateClient {
  SearchIsolateClient();

  Isolate? _isolate;
  SendPort? _commands;
  final ReceivePort _replies = ReceivePort();
  StreamSubscription? _replySub;
  final Map<int, Completer<SearchIsolateResult>> _inFlight = {};
  int _latestIssued = -1;
  String? _preparedKey;
  bool _disposed = false;
  Future<void>? _starting;

  Future<void> start() {
    if (_starting != null) return _starting!;
    _starting = _start();
    return _starting!;
  }

  Future<void> _start() async {
    if (_disposed) return;
    final ready = Completer<SendPort>();
    _replySub = _replies.listen((message) {
      if (message is! Map<String, dynamic>) return;
      final type = message['type'];
      if (type == 'ready') {
        if (!ready.isCompleted) ready.complete(message['port'] as SendPort);
        return;
      }
      final generation = (message['generation'] as num?)?.toInt() ?? -1;
      final completer = _inFlight.remove(generation);
      if (completer == null || completer.isCompleted) return;
      if (generation != _latestIssued) {
        completer.complete(const (
            indices: <int>[], suggestion: null));
        return;
      }
      if (type == 'error') {
        completer.completeError(StateError(message['message'] as String? ?? ''));
        return;
      }
      completer.complete((
        indices: (message['indices'] as List? ?? const []).cast<int>(),
        suggestion: message['suggestion'] as String?,
      ));
    });
    _isolate = await Isolate.spawn(searchIsolateEntry, _replies.sendPort);
    _commands = await ready.future;
  }

  void prepare({
    required String key,
    required List<String> haystacks,
    required List<String> suggestHaystacks,
  }) {
    final port = _commands;
    if (_disposed || port == null) return;
    if (_preparedKey == key) return;
    _preparedKey = key;
    port.send({
      'type': 'prepare',
      'key': key,
      'haystacks': haystacks,
      'suggestHaystacks': suggestHaystacks,
    });
  }

  Future<SearchIsolateResult> search({
    required String key,
    required String query,
    required int limit,
    required int generation,
  }) async {
    if (_disposed || generation < _latestIssued) {
      return const (indices: <int>[], suggestion: null);
    }
    final port = _commands;
    if (port == null) await start();
    _latestIssued = generation;
    final completer = Completer<SearchIsolateResult>();
    _inFlight[generation] = completer;
    _commands!.send({
      'type': 'query',
      'key': key,
      'generation': generation,
      'query': query,
      'limit': limit,
    });
    return completer.future;
  }

  void dispose() {
    _disposed = true;
    for (final completer in _inFlight.values) {
      if (!completer.isCompleted) {
        completer.complete(const (
            indices: <int>[], suggestion: null));
      }
    }
    _inFlight.clear();
    _preparedKey = null;
    _commands?.send({'type': 'close'});
    _replySub?.cancel();
    _replies.close();
    _isolate?.kill();
  }
}
