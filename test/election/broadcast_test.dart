import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/broadcast.dart';
import 'package:toice/native_bridge/native_bridge.g.dart' show ThermalState;

void main() {
  group('RssiVector', () {
    test('worstDbm is the minimum (weakest) link', () {
      const v = RssiVector({'a': -55, 'b': -80, 'c': -60});
      expect(v.worstDbm, -80);
    });

    test('worstDbm is null with no peers', () {
      expect(const RssiVector({}).worstDbm, isNull);
    });
  });

  group('ElectionBroadcast JSON round-trip', () {
    test('preserves every field', () {
      const b = ElectionBroadcast(
        senderId: 'dev-1',
        rssi: RssiVector({'dev-2': -55, 'dev-3': -72}),
        batteryPercent: 48.5,
        thermal: ThermalState.serious,
        hostCapable: true,
        timestampMs: 123456,
      );

      final back = ElectionBroadcast.fromJson(b.toJson());

      expect(back.senderId, b.senderId);
      expect(back.rssi.byPeer, b.rssi.byPeer);
      expect(back.batteryPercent, b.batteryPercent);
      expect(back.thermal, b.thermal);
      expect(back.hostCapable, b.hostCapable);
      expect(back.timestampMs, b.timestampMs);
    });
  });

  group('rssiScoreFromDbm', () {
    test('clamps below usable range to 0', () {
      expect(rssiScoreFromDbm(-100), 0.0);
    });
    test('clamps above excellent to 100', () {
      expect(rssiScoreFromDbm(-30), 100.0);
    });
    test('midpoint -65 dBm scores ~50', () {
      expect(rssiScoreFromDbm(-65), closeTo(50.0, 0.5));
    });
    test('monotonic: stronger dBm scores higher', () {
      expect(rssiScoreFromDbm(-50), greaterThan(rssiScoreFromDbm(-70)));
    });
  });

  group('thermalScoreFromState', () {
    test('nominal is best, critical is worst', () {
      expect(thermalScoreFromState(ThermalState.nominal), 100.0);
      expect(thermalScoreFromState(ThermalState.critical), 0.0);
    });
    test('monotonic across the ordinal', () {
      final scores = ThermalState.values.map(thermalScoreFromState).toList();
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i], lessThan(scores[i - 1]));
      }
    });
  });
}
