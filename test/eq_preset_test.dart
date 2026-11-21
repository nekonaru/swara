import 'package:flutter_test/flutter_test.dart';
import 'package:swara/models/eq_preset.dart';

void main() {
  group('EqPreset', () {
    test('clamps and pads gains to five finite bands', () {
      final gains = EqPreset.clampGains([99, -99, double.nan, 1.5]);
      expect(gains.length, 5);
      expect(gains[0], 6);
      expect(gains[1], -6);
      expect(gains[2], 0);
      expect(gains[3], 1.5);
      expect(gains[4], 0);
    });

    test('round trips through JSON', () {
      const preset = EqPreset(
          id: '1', name: 'Warm', gains: [-1, 0.5, 2, 1, -0.5]);
      final decoded = decodeEqPresets(encodeEqPresets([preset]));
      expect(decoded.length, 1);
      expect(decoded.first.name, 'Warm');
      expect(decoded.first.gains, preset.gains);
    });

    test('malformed JSON and bad rows are dropped', () {
      expect(decodeEqPresets('not json'), isEmpty);
      expect(
          decodeEqPresets(
              '[{"id":"1","name":"ok","gains":[0,0,0,0,0]},{"id":"","name":"x","gains":[]}]'),
          hasLength(1));
      expect(decodeEqPresets('{"not":"a list"}'), isEmpty);
    });
  });
}
