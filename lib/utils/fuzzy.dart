// Tolerant search helpers used by the search screen.
// Pure functions with no dependencies so they are easy to unit test.

// Hoisted so the patterns are compiled once per app instead of twice per
// normalize() call. normalize() runs for every song on every search query,
// so recompiling regexes there dominated the search cost.
final RegExp _nonAlnumRun = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _wsRun = RegExp(r'\s+');

// Lowercase the text, replace every run of non-alphanumeric characters
// with a single space, then collapse whitespace and trim.
// Unicode letters and numbers are kept, so non-Latin scripts still work.
String normalize(String text) {
  final lower = text.toLowerCase();
  final spaced = lower.replaceAll(_nonAlnumRun, ' ');
  final collapsed = spaced.replaceAll(_wsRun, ' ');
  return collapsed.trim();
}

// Return true when every normalized query token appears as a substring
// of the normalized haystack. Token order does not matter, so
// "faded alan walker" matches "Faded - Alan Walker".
// An empty or blank query matches everything (vacuous truth).
// A non-empty query never matches an empty haystack.
bool fuzzyMatch(String haystack, String query) =>
    fuzzyMatchNormalized(normalize(haystack), normalize(query));

// Core of [fuzzyMatch] on already normalized text. The search isolate calls
// this once per song with a query normalized once per run, so neither side
// pays for two regex passes per row.
bool fuzzyMatchNormalized(String normalizedHaystack, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  if (normalizedHaystack.isEmpty) return false;
  final tokens = normalizedQuery.split(' ');
  for (final token in tokens) {
    if (token.isEmpty) continue;
    if (!normalizedHaystack.contains(token)) return false;
  }
  return true;
}

// How many single character edits a query token may be away from a word
// in the haystack and still count as a typo.
//
// The tolerance scales with length because a fixed tolerance would either
// let anything through on short words or reject everything on long ones:
// "feald" against "faded" needs 2 edits, while "abcdefgh" must match exactly.
int typoToleranceFor(String token) {
  if (token.length <= 3) return 0;
  if (token.length <= 6) return 1;
  return 2;
}

// Damerau-Levenshtein (optimal string alignment) distance, bounded by
// [limit] for speed.
//
// The transposition case matters more than it looks: plain Levenshtein
// counts a swapped pair as two edits, so "feald" would need a tolerance of 2
// against "faded", which is far too loose for a five letter word. Counting a
// transposition as a single edit is what makes the feature usable at all,
// since swapped letters are the most common typo.
//
// Returns a value greater than [limit] as soon as the distance is known to
// exceed it, so a long token against a huge haystack bails early.
int editDistanceWithin(String a, String b, int limit) {
  if (a == b) return 0;
  final ar = a.runes.toList(growable: false);
  final br = b.runes.toList(growable: false);
  final n = ar.length;
  final m = br.length;
  if (n == 0) return m;
  if (m == 0) return n;
  if ((n - m).abs() > limit) return limit + 1;

  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (i) => i);
  var cur = List<int>.filled(m + 1, 0);

  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    var rowBest = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = ar[i - 1] == br[j - 1] ? 0 : 1;
      var best = prev[j] + 1; // deletion
      final ins = cur[j - 1] + 1;
      if (ins < best) best = ins;
      final sub = prev[j - 1] + cost;
      if (sub < best) best = sub;
      if (i > 1 &&
          j > 1 &&
          ar[i - 1] == br[j - 2] &&
          ar[i - 2] == br[j - 1]) {
        final swap = prev2[j - 2] + 1;
        if (swap < best) best = swap;
      }
      cur[j] = best;
      if (best < rowBest) rowBest = best;
    }
    if (rowBest > limit) return limit + 1;
    final old = prev2;
    prev2 = prev;
    prev = cur;
    cur = old;
  }
  return prev[m];
}

/// Whether [token] is at most [tolerance] edits away from some word inside
/// [haystack]. This is the fallback that makes "feald" find "Faded".
bool tokenMatchesWithTypos(String haystack, String token, int tolerance) {
  if (tolerance <= 0) return false;
  if (token.isEmpty || haystack.isEmpty) return false;
  final tokenRunes = token.runes.length;
  for (final word in haystack.split(' ')) {
    if (word.isEmpty) continue;
    // A length gap beyond the tolerance can never be closed by edits.
    if ((word.runes.length - tokenRunes).abs() > tolerance) continue;
    if (editDistanceWithin(token, word, tolerance) <= tolerance) return true;
  }
  return false;
}

/// Match with typo tolerance: exact substring wins first, then each token is
/// allowed to be a near miss against a word in the haystack.
///
/// A token only matches tolerantly when NO word in the haystack contains it,
/// so an exact hit is never displaced by a fuzzy one.
bool fuzzyMatchLoose(String haystack, String query) =>
    fuzzyMatchLooseNormalized(normalize(haystack), normalize(query));

/// Core of [fuzzyMatchLoose] on already normalized text, same reasoning as
/// [fuzzyMatchNormalized]: the isolate normalizes once per row and per run.
bool fuzzyMatchLooseNormalized(
    String normalizedHaystack, String normalizedQuery) {
  if (normalizedQuery.isEmpty) return true;
  if (normalizedHaystack.isEmpty) return false;
  for (final token in normalizedQuery.split(' ')) {
    if (token.isEmpty) continue;
    if (normalizedHaystack.contains(token)) continue;
    if (!tokenMatchesWithTypos(
        normalizedHaystack, token, typoToleranceFor(token))) {
      return false;
    }
  }
  return true;
}

/// A near miss suggestion for a query that returned nothing.
///
/// Returns null when the query is blank or when nothing close enough exists.
/// Only single word queries are suggested: a multi word typo is far too
/// ambiguous to guess.
///
/// The suggestion window is deliberately one edit wider than the match
/// window. A suggestion is only offered, never acted on, so it can afford to
/// be a little more generous than the matching rule.
String? suggestFor(String query, Iterable<String> haystacks) {
  final normalizedQuery = normalize(query);
  if (normalizedQuery.isEmpty || normalizedQuery.contains(' ')) return null;
  final matchTolerance = typoToleranceFor(normalizedQuery);
  if (matchTolerance <= 0) return null;
  final tolerance = matchTolerance + 1;

  String? best;
  var bestDistance = tolerance + 1;
  final seen = <String>{};
  final queryRunes = normalizedQuery.runes.length;
  for (final haystack in haystacks) {
    for (final word in normalize(haystack).split(' ')) {
      if (word.isEmpty || !seen.add(word)) continue;
      if ((word.runes.length - queryRunes).abs() > tolerance) continue;
      final distance = editDistanceWithin(normalizedQuery, word, tolerance);
      if (distance <= tolerance && distance < bestDistance) {
        bestDistance = distance;
        best = word;
      }
    }
  }
  return best;
}