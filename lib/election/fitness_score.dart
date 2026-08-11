/// Composite host-fitness scoring (ADR-003).
///
/// Pure function: every device runs the identical computation over the same
/// broadcast data so all devices arrive at the same ranking. No I/O, no state.
///
/// This is the scoring primitive only. Broadcast cadence, hysteresis, and the
/// intent/ack handoff protocol are Phase 2, not here.
library;

/// Relative weights for the three score components (ADR-003).
///
/// RSSI is weighted highest: it directly affects connectivity for everyone.
/// Battery and thermal are longevity concerns, weighted lower. Weights are
/// tunable and must be validated empirically during testing.
class FitnessWeights {
  const FitnessWeights({
    this.rssi = 0.5,
    this.battery = 0.3,
    this.thermal = 0.2,
  });

  final double rssi;
  final double battery;
  final double thermal;

  double get sum => rssi + battery + thermal;
}

/// Curve a raw battery percentage (0-100) into a score that drops sharply
/// below ~30% (ADR-003: "curved to penalize sharply below ~30%").
///
/// Above 30% the score tracks the percentage linearly. At or below 30% it
/// falls on a quadratic so a 20% battery scores far worse than 40%.
double batteryScoreFromPercent(double percent) {
  final p = percent.clamp(0.0, 100.0);
  if (p >= 30.0) return p;
  // Quadratic ramp: 0 at 0%, 30 at 30%, convex in between.
  final r = p / 30.0;
  return 30.0 * r * r;
}

/// Weighted sum of the three normalized (0-100) component scores, clamped to
/// 0-100. No component is a hard cutoff (ADR-003): a device in poor thermal
/// state can still win if every other candidate is worse.
///
/// Weights are normalized by their sum, so callers may pass unnormalized
/// weights (e.g. 5/3/2) and still get a 0-100 result.
double computeFitnessScore({
  required double rssiScore,
  required double batteryScore,
  required double thermalScore,
  FitnessWeights weights = const FitnessWeights(),
}) {
  assert(weights.sum > 0, 'weights must sum to a positive value');
  final r = rssiScore.clamp(0.0, 100.0);
  final b = batteryScore.clamp(0.0, 100.0);
  final t = thermalScore.clamp(0.0, 100.0);
  final weighted =
      (weights.rssi * r) + (weights.battery * b) + (weights.thermal * t);
  return (weighted / weights.sum).clamp(0.0, 100.0);
}
