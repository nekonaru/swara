import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/search_filter.dart';

// Regression guards for the extracted search matcher. The search screen now
// runs this in a background isolate, so the contract of the plain in/out
// maps is what keeps results identical to the old in method version.

void main() {
  Map<String, dynamic> run({
    required List<String> haystacks,
    required List<String> suggestHaystacks,
    required String query,
    int limit = 500,
  }) {
    return filterSongsIsolate(<String, dynamic>{
      'haystacks': haystacks,
      'suggestHaystacks': suggestHaystacks,
      'query': query,
      'limit': limit,
    });
  }

  test('exact matches are returned before typo tolerant matches', () {
    final res = run(
      haystacks: [
        'faded alan walker', // exact for "faded"
        'fadee remix', // one edit off, only in the loose pass
        'faded', // exact
      ],
      suggestHaystacks: const [],
      query: 'faded',
    );
    // Index 1 (the near miss) must never outrank the real exact hits.
    expect((res['indices'] as List).cast<int>(), [0, 2, 1]);
    expect(res['suggestion'], isNull);
  });

  test('a loose match still returns results', () {
    final res = run(
      haystacks: const ['fadee', 'something else'],
      suggestHaystacks: const [],
      query: 'faded',
    );
    expect((res['indices'] as List).cast<int>(), [0]);
    expect(res['suggestion'], isNull,
        reason: 'a spelling hint is only offered when nothing matched');
  });

  test('a spelling suggestion appears only when nothing matched', () {
    final res = run(
      haystacks: const ['never matches this'],
      suggestHaystacks: const ['faded alan walker'],
      query: 'fadde',
    );
    expect((res['indices'] as List).cast<int>(), isEmpty);
    expect(res['suggestion'], 'faded');
  });

  test('token order does not matter for the exact pass', () {
    final res = run(
      haystacks: const ['Faded - Alan Walker'],
      suggestHaystacks: const [],
      query: 'alan faded',
    );
    expect((res['indices'] as List).cast<int>(), [0]);
  });

  test('the safety cap limits the returned indices', () {
    final res = run(
      haystacks: List<String>.filled(20, 'faded'),
      suggestHaystacks: const [],
      query: 'faded',
      limit: 5,
    );
    expect((res['indices'] as List).cast<int>(), [0, 1, 2, 3, 4]);
    expect((res['indices'] as List).length, 5);
  });

  test('an unknown query returns no indices and no suggestion', () {
    final res = run(
      haystacks: const ['faded'],
      suggestHaystacks: const ['faded'],
      query: 'zzzzqqqq',
    );
    expect((res['indices'] as List).cast<int>(), isEmpty);
    // Too far off even for the wider suggestion window.
    expect(res['suggestion'], isNull);
  });
}
