/// Deterministic host-election ranking (ADR-003).
///
/// Ranks host candidates by composite fitness so every device, given the same
/// set of [ElectionBroadcast]s, arrives at the identical winner. Pure function,
/// no state. Hysteresis (should we actually switch?) is a separate gate.
library;

import 'package:toice/election/broadcast.dart';
import 'package:toice/election/fitness_score.dart';

/// One candidate's computed fitness, ready to rank.
class Ranked {
  const Ranked(this.deviceId, this.score);

  final String deviceId;
  final double score;
}

/// Rank host-capable candidates best-first (ADR-003).
///
/// - iOS / non-capable devices ([ElectionBroadcast.hostCapable] false) are
///   excluded: they cannot host an AP (ADR-003 addendum).
/// - A candidate with no measured links ([RssiVector.worstDbm] null) is
///   excluded: it cannot be scored on its worst link, the ADR-003 basis.
/// - Ties break by deviceId ascending, so ranking is total and deterministic
///   across devices with no shared clock.
List<Ranked> rankCandidates(
  Iterable<ElectionBroadcast> broadcasts, {
  FitnessWeights weights = const FitnessWeights(),
}) {
  final ranked = <Ranked>[];
  for (final b in broadcasts) {
    if (!b.hostCapable) continue;
    final worst = b.rssi.worstDbm;
    if (worst == null) continue;
    final score = computeFitnessScore(
      rssiScore: rssiScoreFromDbm(worst),
      batteryScore: batteryScoreFromPercent(b.batteryPercent),
      thermalScore: thermalScoreFromState(b.thermal),
      weights: weights,
    );
    ranked.add(Ranked(b.senderId, score));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.deviceId.compareTo(b.deviceId);
  });
  return ranked;
}

/// The best host candidate, or null if none is eligible.
Ranked? bestCandidate(
  Iterable<ElectionBroadcast> broadcasts, {
  FitnessWeights weights = const FitnessWeights(),
}) {
  final ranked = rankCandidates(broadcasts, weights: weights);
  return ranked.isEmpty ? null : ranked.first;
}
