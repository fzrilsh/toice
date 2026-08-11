import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/broadcast.dart';
import 'package:toice/election/ranking.dart';
import 'package:toice/native_bridge/native_bridge.g.dart' show ThermalState;

ElectionBroadcast bc(
  String id, {
  required int worstDbm,
  double battery = 100,
  ThermalState thermal = ThermalState.nominal,
  bool hostCapable = true,
}) => ElectionBroadcast(
  senderId: id,
  rssi: RssiVector({'peer': worstDbm}),
  batteryPercent: battery,
  thermal: thermal,
  hostCapable: hostCapable,
  timestampMs: 0,
);

void main() {
  test('ranks best fitness first', () {
    final ranked = rankCandidates([
      bc('weak', worstDbm: -85, battery: 20, thermal: ThermalState.serious),
      bc('strong', worstDbm: -45, battery: 95),
    ]);
    expect(ranked.map((r) => r.deviceId), ['strong', 'weak']);
  });

  test('excludes non-host-capable (iOS) devices', () {
    final ranked = rankCandidates([
      bc('iphone', worstDbm: -40, hostCapable: false),
      bc('android', worstDbm: -70),
    ]);
    expect(ranked.map((r) => r.deviceId), ['android']);
  });

  test('excludes candidates with no measured links', () {
    final ranked = rankCandidates([
      ElectionBroadcast(
        senderId: 'blind',
        rssi: const RssiVector({}),
        batteryPercent: 100,
        thermal: ThermalState.nominal,
        hostCapable: true,
        timestampMs: 0,
      ),
      bc('seen', worstDbm: -60),
    ]);
    expect(ranked.map((r) => r.deviceId), ['seen']);
  });

  test('ties break by deviceId ascending, deterministically', () {
    final ranked = rankCandidates([
      bc('zeta', worstDbm: -50),
      bc('alpha', worstDbm: -50),
    ]);
    expect(ranked.map((r) => r.deviceId), ['alpha', 'zeta']);
    expect(ranked[0].score, ranked[1].score);
  });

  test('scores a candidate on its worst link, not its best', () {
    final wide = ElectionBroadcast(
      senderId: 'wide',
      rssi: const RssiVector({'a': -40, 'b': -88}),
      batteryPercent: 100,
      thermal: ThermalState.nominal,
      hostCapable: true,
      timestampMs: 0,
    );
    final tight = bc('tight', worstDbm: -55);
    // wide has a -40 link but a -88 link drags it below tight's uniform -55.
    expect(bestCandidate([wide, tight])!.deviceId, 'tight');
  });

  test('bestCandidate is null when nobody is eligible', () {
    expect(
      bestCandidate([bc('ios', worstDbm: -40, hostCapable: false)]),
      isNull,
    );
    expect(bestCandidate([]), isNull);
  });
}
