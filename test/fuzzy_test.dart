import 'package:flutter_test/flutter_test.dart';
import 'package:swara/utils/fuzzy.dart';

// Unit tests for the tolerant search helpers in lib/utils/fuzzy.dart.
void main() {
  group('normalize', () {
    test('lowercases input', () {
      expect(normalize('Faded Alan Walker'), 'faded alan walker');
    });

    test('replaces dash with space', () {
      expect(normalize('Faded - Alan Walker'), 'faded alan walker');
    });

    test('replaces underscore with space', () {
      expect(normalize('faded_alan_walker'), 'faded alan walker');
    });

    test('removes parentheses', () {
      expect(normalize('Faded (Remix)'), 'faded remix');
    });

    test('collapses multiple spaces and trims', () {
      expect(normalize('  faded   alan   walker  '), 'faded alan walker');
    });

    test('handles empty and blank input', () {
      expect(normalize(''), '');
      expect(normalize('   '), '');
    });

    test('keeps digits', () {
      expect(normalize('Top 50 - 2024 Hits'), 'top 50 2024 hits');
    });
  });

  group('fuzzyMatch', () {
    test('matches tokens in any order', () {
      expect(fuzzyMatch('Faded - Alan Walker', 'walker faded'), isTrue);
    });

    test('matches the example query against dash separated haystack', () {
      expect(fuzzyMatch('Faded - Alan Walker', 'faded alan walker'), isTrue);
    });

    test('requires every query token to be present', () {
      expect(fuzzyMatch('Faded - Alan Walker', 'faded alan avicii'), isFalse);
    });

    test('matches token as substring of haystack', () {
      expect(fuzzyMatch('Alan Walker', 'alan walk'), isTrue);
    });

    test('is case insensitive', () {
      expect(fuzzyMatch('Faded - Alan Walker', 'FADED ALAN'), isTrue);
    });

    test('ignores punctuation in query and haystack', () {
      expect(fuzzyMatch('Faded (Alan_Walker)', 'faded alan walker'), isTrue);
    });

    test('matches multi-field haystack built from song fields', () {
      const haystack = 'Faded Alan Walker Different Album Pop';
      expect(fuzzyMatch(haystack, 'faded pop'), isTrue);
      expect(fuzzyMatch(haystack, 'faded rock'), isFalse);
    });

    test('empty query matches everything', () {
      expect(fuzzyMatch('Faded - Alan Walker', ''), isTrue);
      expect(fuzzyMatch('Faded - Alan Walker', '   '), isTrue);
      expect(fuzzyMatch('', ''), isTrue);
    });

    test('non-empty query does not match empty haystack', () {
      expect(fuzzyMatch('', 'faded'), isFalse);
    });

    test('unicode letters are kept and matched', () {
      expect(normalize('さくら SAKURA'), 'さくら sakura');
      expect(fuzzyMatch('さくら SAKURA', 'sakura さくら'), isTrue);
      expect(fuzzyMatch('さくら', 'sakura'), isFalse);
    });
  });
}
