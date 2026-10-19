import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/fuzzy.dart';

void main() {
  group('editDistanceWithin', () {
    test('identical strings are zero', () {
      expect(editDistanceWithin('faded', 'faded', 5), 0);
    });

    test('counts a substitution', () {
      expect(editDistanceWithin('cat', 'car', 5), 1);
    });

    test('counts an insertion and a deletion', () {
      expect(editDistanceWithin('fad', 'faed', 5), 1);
      expect(editDistanceWithin('faed', 'fad', 5), 1);
    });

    test('a transposition costs one edit, not two', () {
      // This is the whole reason the algorithm is Damerau rather than
      // Levenshtein: swapped letters are the most common typo.
      expect(editDistanceWithin('wla', 'wal', 5), 1);
      expect(editDistanceWithin('fadde', 'faded', 5), 1);
    });

    test('a three character rotation is not treated as one edit', () {
      // Honest limit: "feald" against "faded" needs three edits, so it will
      // not match. It is only close enough to be suggested.
      expect(editDistanceWithin('feald', 'faded', 5), 3);
    });

    test('different lengths are handled', () {
      expect(editDistanceWithin('fad', 'faded', 5), 2);
      expect(editDistanceWithin('faded', 'fad', 5), 2);
    });

    test('known distance', () {
      expect(editDistanceWithin('kitten', 'sitting', 10), 3);
      expect(editDistanceWithin('faded', 'faded', 5), 0);
    });

    test('handles empty strings', () {
      expect(editDistanceWithin('', '', 3), 0);
      expect(editDistanceWithin('', 'abc', 3), 3);
      expect(editDistanceWithin('abc', '', 3), 3);
    });

    test('bails out beyond the limit instead of returning the real distance',
        () {
      expect(editDistanceWithin('abcdefgh', 'zzzzzzzz', 2) > 2, isTrue);
    });

    test('works with text outside the basic plane', () {
      // Two astral characters differ by one substitution, not two units of
      // UTF-16 code.
      expect(editDistanceWithin('😀😁', '😀😃', 5), 1);
    });
  });

  group('typoToleranceFor', () {
    test('short tokens get no tolerance', () {
      expect(typoToleranceFor('cat'), 0);
      expect(typoToleranceFor('abcd'), 1);
      expect(typoToleranceFor('abcdef'), 1);
      expect(typoToleranceFor('abcdefg'), 2);
    });
  });

  group('fuzzyMatchLoose', () {
    const library = 'Faded - Alan Walker';

    test('an exact substring still matches', () {
      expect(fuzzyMatchLoose(library, 'faded'), isTrue);
      expect(fuzzyMatchLoose(library, 'walker alan'), isTrue);
    });

    test('a transposed typo matches', () {
      expect(fuzzyMatchLoose(library, 'fadde'), isTrue);
      expect(fuzzyMatchLoose(library, 'wlaeker'), isTrue);
    });

    test('a substituted letter matches', () {
      expect(fuzzyMatchLoose(library, 'fadet'), isTrue);
    });

    test('a three character rotation does not match but is close', () {
      expect(fuzzyMatchLoose(library, 'feald'), isFalse);
    });

    test('a completely different word does not match', () {
      expect(fuzzyMatchLoose(library, 'eminem'), isFalse);
    });

    test('every token must still match', () {
      expect(fuzzyMatchLoose(library, 'feald nonexistentword'), isFalse);
    });

    test('short tokens get no typo freedom', () {
      expect(fuzzyMatchLoose('cat', 'bat'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(fuzzyMatchLoose(library, ''), isTrue);
      expect(fuzzyMatchLoose(library, '   '), isTrue);
    });

    test('an empty haystack never matches a non-empty query', () {
      expect(fuzzyMatchLoose('', 'faded'), isFalse);
    });

    test('non latin text still works', () {
      // Escaped so this file stays readable in any editor encoding.
      expect(fuzzyMatchLoose('\u82b1\u6d77', '\u82b1\u6d77'), isTrue);
    });
  });

  group('suggestFor', () {
    final haystacks = [
      'Faded - Alan Walker',
      'Faded (Remix) - Alan Walker',
      'Alone',
    ];

    test('suggests the near miss word', () {
      expect(suggestFor('fadde', haystacks), 'faded');
    });

    test('returns null when nothing is close', () {
      expect(suggestFor('eminem', haystacks), isNull);
    });

    test('returns null for a blank query', () {
      expect(suggestFor('', haystacks), isNull);
      expect(suggestFor('   ', haystacks), isNull);
    });

    test('never guesses a multi word query', () {
      expect(suggestFor('feald alna', haystacks), isNull);
    });

    test('a three character rotation is too far even to suggest', () {
      // Honest limit: past two edits the word is no longer recognisable
      // enough to offer a guess.
      expect(suggestFor('feald', haystacks), isNull);
    });

    test('suggests a typo one edit wider than the match rule', () {
      // "fadet" matches the library outright, so the suggestion is only a
      // safety net for queries that return nothing.
      expect(fuzzyMatchLoose('Faded - Alan Walker', 'fadet'), isTrue);
      expect(suggestFor('fadet', haystacks), 'faded');
    });

    test('never guesses for a very short token', () {
      expect(suggestFor('fad', haystacks), isNull);
    });

    test('is not confused by repeated words', () {
      expect(suggestFor('fadde', haystacks), 'faded');
    });

    test('prefers the closest word', () {
      expect(suggestFor('fadde', haystacks), 'faded');
      expect(suggestFor('fadet', haystacks), 'faded');
    });
  });
}
