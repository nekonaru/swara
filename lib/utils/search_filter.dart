// Search matching for the search screen, extracted so it can run inside a
// background isolate.
//
// Why this must be off the UI thread: matching normalizes every haystack with
// two regular expressions, and the typo pass can run a bounded edit distance
// against every word of every song. On a library of a few thousand songs that
// used to cost a whole frame per keystroke, which showed up as stutter while
// typing a query.

import 'fuzzy.dart';

/// One search run against a prebuilt haystack list.
///
/// Plain data in and out (a Map), so [filterSongsIsolate] never depends on
/// class transfer semantics across the isolate boundary.
///
/// Input keys:
///   haystacks         one entry per song, built for the active filter tab
///   suggestHaystacks  one "title artist album" entry per song, only read
///                     when nothing matched
///   query             raw user text
///   limit             safety cap for the returned index list
///
/// Output keys:
///   indices     matching row indices, exact matches first, capped
///   suggestion  near miss hint, or null when something matched
Map<String, dynamic> filterSongsIsolate(Map<String, dynamic> input) {
  final haystacks = (input['haystacks'] as List).cast<String>();
  final suggestHaystacks = (input['suggestHaystacks'] as List).cast<String>();
  final query = input['query'] as String;
  final limit = input['limit'] as int;

  // Normalize the query once per run and each haystack once per row. The old
  // path normalized both sides again inside every fuzzyMatch/fuzzyMatchLoose
  // call, which multiplied the two regex passes by the library size twice.
  final normalizedQuery = normalize(query);

  // Two passes: exact substring matches first, then typo tolerant matches
  // appended after them. Running one loose pass over everything would let a
  // near miss outrank the song the user actually typed.
  final exact = <int>[];
  final loose = <int>[];
  for (var i = 0; i < haystacks.length; i++) {
    final normalizedHaystack = normalize(haystacks[i]);
    if (fuzzyMatchNormalized(normalizedHaystack, normalizedQuery)) {
      exact.add(i);
    } else if (fuzzyMatchLooseNormalized(normalizedHaystack, normalizedQuery)) {
      loose.add(i);
    }
  }

  // Only offer a spelling hint when the typo pass found nothing, otherwise
  // it would nag while real results are on screen.
  String? suggestion;
  if (exact.isEmpty && loose.isEmpty) {
    suggestion = suggestFor(query, suggestHaystacks);
  }

  // Safety cap only, never a paging window. Applied here so the caller
  // never copies more than the limit back across the isolate boundary.
  final matched = exact.isEmpty ? loose : <int>[...exact, ...loose];
  final indices =
      matched.length > limit ? matched.sublist(0, limit) : matched;

  return <String, dynamic>{
    'indices': indices,
    'suggestion': suggestion,
  };
}
