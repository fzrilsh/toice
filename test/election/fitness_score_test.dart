import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/fitness_score.dart';

void main() {
  group('computeFitnessScore', () {
    test('equal scores yield that score regardless of weights', () {
      expect(
        computeFitnessScore(rssiScore: 80, batteryScore: 80, thermalScore: 80),
        closeTo(80, 1e-9),
      );
    });

    test('normalizes by weight sum (unnormalized weights allowed)', () {
      final score = computeFitnessScore(
        rssiScore: 100,
        batteryScore: 0,
        thermalScore: 0,
        weights: const FitnessWeights(rssi: 5, battery: 3, thermal: 2),
      );
      // 5/(5+3+2) * 100 = 50
      expect(score, closeTo(50, 1e-9));
    });

    test('RSSI weighted highest under default weights (ADR-003)', () {
      final rssiHigh = computeFitnessScore(
        rssiScore: 100,
        batteryScore: 0,
        thermalScore: 0,
      );
      final batteryHigh = computeFitnessScore(
        rssiScore: 0,
        batteryScore: 100,
        thermalScore: 0,
      );
      expect(rssiHigh, greaterThan(batteryHigh));
    });

    test('no hard cutoff: worst thermal still contributes', () {
      final score = computeFitnessScore(
        rssiScore: 90,
        batteryScore: 90,
        thermalScore: 0,
      );
      expect(score, greaterThan(0));
    });

    test('clamps out-of-range component inputs', () {
      expect(
        computeFitnessScore(
          rssiScore: 200,
          batteryScore: 200,
          thermalScore: 200,
        ),
        closeTo(100, 1e-9),
      );
      expect(
        computeFitnessScore(
          rssiScore: -50,
          batteryScore: -50,
          thermalScore: -50,
        ),
        closeTo(0, 1e-9),
      );
    });
  });

  group('batteryScoreFromPercent', () {
    test('linear at or above 30%', () {
      expect(batteryScoreFromPercent(100), closeTo(100, 1e-9));
      expect(batteryScoreFromPercent(30), closeTo(30, 1e-9));
    });

    test('penalizes sharply below 30% (ADR-003 curve)', () {
      // 15% would be 15 if linear; curve must score it strictly lower.
      expect(batteryScoreFromPercent(15), lessThan(15));
      expect(batteryScoreFromPercent(0), closeTo(0, 1e-9));
    });

    test('monotonic increasing', () {
      expect(
        batteryScoreFromPercent(10),
        lessThan(batteryScoreFromPercent(20)),
      );
      expect(
        batteryScoreFromPercent(20),
        lessThan(batteryScoreFromPercent(40)),
      );
    });
  });
}
