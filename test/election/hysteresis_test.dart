import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/hysteresis.dart';

void main() {
  late DateTime now;
  HysteresisGate gate() => HysteresisGate(
    margin: 10,
    duration: const Duration(seconds: 3),
    clock: () => now,
  );

  setUp(() => now = DateTime(2026, 1, 1));

  test('does not switch before the sustained duration elapses', () {
    final g = gate();
    expect(
      g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60),
      isFalse,
    );
    now = now.add(const Duration(seconds: 2));
    expect(
      g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60),
      isFalse,
    );
  });

  test('switches once the lead holds for the full duration', () {
    final g = gate();
    g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60);
    now = now.add(const Duration(seconds: 3));
    expect(
      g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60),
      isTrue,
    );
  });

  test('a lead below the margin never starts the timer', () {
    final g = gate();
    g.evaluate(challengerId: 'b', challengerScore: 65, currentHostScore: 60);
    now = now.add(const Duration(seconds: 10));
    expect(
      g.evaluate(challengerId: 'b', challengerScore: 65, currentHostScore: 60),
      isFalse,
    );
    expect(g.pendingLeader, isNull);
  });

  test('a lapse in the lead resets the timer (anti-flap)', () {
    final g = gate();
    g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60);
    now = now.add(const Duration(seconds: 2));
    // Lead collapses below margin: timer resets.
    g.evaluate(challengerId: 'b', challengerScore: 62, currentHostScore: 60);
    now = now.add(const Duration(seconds: 2));
    // Back ahead, but the clock restarts, so not yet 3s.
    expect(
      g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60),
      isFalse,
    );
  });

  test('a new challenger restarts the sustained window', () {
    final g = gate();
    g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60);
    now = now.add(const Duration(seconds: 2));
    // Different challenger takes the lead: its own timer starts now.
    expect(
      g.evaluate(challengerId: 'c', challengerScore: 85, currentHostScore: 60),
      isFalse,
    );
    expect(g.pendingLeader, 'c');
    now = now.add(const Duration(seconds: 3));
    expect(
      g.evaluate(challengerId: 'c', challengerScore: 85, currentHostScore: 60),
      isTrue,
    );
  });

  test(
    'null host (bootstrap): any qualifying challenger accrues immediately',
    () {
      final g = gate();
      g.evaluate(
        challengerId: 'b',
        challengerScore: 40,
        currentHostScore: null,
      );
      now = now.add(const Duration(seconds: 3));
      expect(
        g.evaluate(
          challengerId: 'b',
          challengerScore: 40,
          currentHostScore: null,
        ),
        isTrue,
      );
    },
  );

  test('no challenger resets pending state', () {
    final g = gate();
    g.evaluate(challengerId: 'b', challengerScore: 80, currentHostScore: 60);
    g.evaluate(challengerId: null, challengerScore: null, currentHostScore: 60);
    expect(g.pendingLeader, isNull);
  });
}
