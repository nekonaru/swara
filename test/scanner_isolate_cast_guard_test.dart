import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the "scan never finds any music" bug.
///
/// The scan hands its work to an isolate through compute(). One of the values
/// that crosses that boundary is the set of excluded folders, which the main
/// thread holds as a Set<String>. The isolate entry used to read it with
/// `(input['excluded'] as List).cast<String>()`, and a Set is not a List, so
/// the cast threw before a single track was processed. Every scan therefore
/// failed outright and the library stayed empty even though permission was
/// granted and music was present on the device.
///
/// The value must be coerced instead of cast, and the sender must pass a
/// plain List so the shape is unambiguous.
void main() {
  String readScanner() => File('lib/services/library_scanner.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('the isolate coerces the excluded folders instead of casting to List',
      () {
    final source = readScanner();
    expect(
      source.contains("(input['excluded'] as List).cast<String>()"),
      isFalse,
      reason: 'casting the excluded folders to List aborts the scan when the '
          'main thread sends a Set, so no track is ever processed',
    );
    expect(
      source.contains('_asStringCollection(input[\'excluded\'])'),
      isTrue,
      reason: 'the excluded folders must be coerced into a Set, which accepts '
          'both a List and a Set arriving across the isolate boundary',
    );
  });

  test('the sender hands the isolate a plain List, not a Set', () {
    final source = readScanner();
    expect(
      source.contains("'excluded': excluded.toList(),"),
      isTrue,
      reason: 'sending a Set across the isolate boundary produced the type '
          'mismatch that failed every scan',
    );
  });

  test('the coercion helper tolerates an unexpected type', () {
    final source = readScanner();
    // The helper must degrade to an empty set rather than throw, so a bad
    // value can never abort a scan again.
    expect(
      source.contains('return <String>{};'),
      isTrue,
      reason: 'an unexpected excluded-folders value must degrade to an empty '
          'set instead of throwing away the whole scan',
    );
  });
}
