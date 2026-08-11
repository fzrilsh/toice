/// Election broadcast payload (ADR-003).
///
/// Every device periodically broadcasts its host-fitness inputs so all devices
/// can run the identical [computeFitnessScore] ranking. This file defines the
/// wire model + JSON codec and the two mappers that turn raw sensor readings
/// into 0-100 component scores. Ranking, hysteresis, and handoff are separate.
library;

import 'package:toice/native_bridge/native_bridge.g.dart' show ThermalState;

/// Per-peer RSSI, as seen by the broadcasting device.
///
/// ADR-003 scores a host candidate on its *worst* link, so the ranking uses the
/// minimum across all peers, not the average. Keyed by peer deviceId, dBm
/// (negative; closer to 0 is stronger).
class RssiVector {
  const RssiVector(this.byPeer);

  final Map<String, int> byPeer;

  /// Worst-case (minimum) dBm across all links, or null if this device sees no
  /// peers yet. A candidate with no measured links cannot be scored on RSSI.
  int? get worstDbm =>
      byPeer.isEmpty ? null : byPeer.values.reduce((a, b) => a < b ? a : b);

  Map<String, Object?> toJson() => byPeer;

  factory RssiVector.fromJson(Map<String, Object?> json) =>
      RssiVector(json.map((k, v) => MapEntry(k, (v as num).toInt())));
}

/// One device's periodic fitness broadcast (ADR-003).
class ElectionBroadcast {
  const ElectionBroadcast({
    required this.senderId,
    required this.rssi,
    required this.batteryPercent,
    required this.thermal,
    required this.hostCapable,
    required this.timestampMs,
  });

  final String senderId;
  final RssiVector rssi;
  final double batteryPercent;
  final ThermalState thermal;

  /// iOS cannot host an AP, so it broadcasts [hostCapable] = false and is
  /// excluded from the host election (ADR-003 addendum).
  final bool hostCapable;

  /// Sender's monotonic clock at emit time; used for staleness, not ordering
  /// across devices (no shared clock in a local mesh).
  final int timestampMs;

  Map<String, Object?> toJson() => {
    'senderId': senderId,
    'rssi': rssi.toJson(),
    'batteryPercent': batteryPercent,
    'thermal': thermal.name,
    'hostCapable': hostCapable,
    'timestampMs': timestampMs,
  };

  factory ElectionBroadcast.fromJson(Map<String, Object?> json) =>
      ElectionBroadcast(
        senderId: json['senderId'] as String,
        rssi: RssiVector.fromJson(
          (json['rssi'] as Map).cast<String, Object?>(),
        ),
        batteryPercent: (json['batteryPercent'] as num).toDouble(),
        thermal: ThermalState.values.byName(json['thermal'] as String),
        hostCapable: json['hostCapable'] as bool,
        timestampMs: (json['timestampMs'] as num).toInt(),
      );
}

/// Map worst-case link RSSI (dBm) to a 0-100 score (ADR-003 rssi_score).
///
/// Linear ramp over the usable range: -90 dBm (edge of usable, 0) to -40 dBm
/// (excellent, 100). Clamped outside. Pass the [RssiVector.worstDbm] so a
/// candidate is scored on its weakest link, per ADR-003.
double rssiScoreFromDbm(int dbm) {
  const worst = -90.0;
  const best = -40.0;
  final r = (dbm - worst) / (best - worst);
  return (r * 100.0).clamp(0.0, 100.0);
}

/// Map OS thermal state to a 0-100 score (ADR-003 thermal_score). Not a hard
/// cutoff: a hot device can still win if every alternative is worse.
double thermalScoreFromState(ThermalState state) => switch (state) {
  ThermalState.nominal => 100.0,
  ThermalState.fair => 66.0,
  ThermalState.serious => 33.0,
  ThermalState.critical => 0.0,
};
