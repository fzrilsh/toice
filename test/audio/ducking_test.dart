import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/ducking.dart';

void main() {
  late DateTime now;
  DuckingEngine engine([DuckingConfig config = const DuckingConfig()]) =>
      DuckingEngine(config: config, clock: () => now);

  setUp(() => now = DateTime(2026, 1, 1));

  test('single speaker above floor gets full gain, others ducked', () {
    final e = engine();
    final gains = e.evaluate({'a': -20, 'b': -70});
    expect(e.activeSpeaker, 'a');
    expect(gains['a'], 0);
    expect(gains['b'], -18);
  });

  test('silence (all below floor) ducks nobody', () {
    final e = engine();
    final gains = e.evaluate({'a': -80, 'b': -90});
    expect(e.activeSpeaker, isNull);
    expect(gains.values, everyElement(0));
  });

  test('a louder challenger does not steal active before hold elapses', () {
    final e = engine();
    e.evaluate({'a': -20, 'b': -70}); // a active
    now = now.add(const Duration(milliseconds: 200));
    final gains = e.evaluate({'a': -30, 'b': -15}); // b now louder
    expect(e.activeSpeaker, 'a'); // hold not yet elapsed
    expect(gains['a'], 0);
    expect(gains['b'], -18);
  });

  test('challenger steals active once it holds the lead for holdTime', () {
    final e = engine();
    e.evaluate({'a': -20, 'b': -70});
    e.evaluate({'a': -30, 'b': -15}); // b challenges, pending starts
    now = now.add(const Duration(milliseconds: 400));
    e.evaluate({'a': -30, 'b': -15}); // hold elapsed
    expect(e.activeSpeaker, 'b');
  });

  test('a brief blip under holdTime never switches (anti-thrash)', () {
    final e = engine();
    e.evaluate({'a': -20, 'b': -70});
    now = now.add(const Duration(milliseconds: 200));
    e.evaluate({'a': -30, 'b': -15}); // b louder briefly
    now = now.add(const Duration(milliseconds: 200));
    e.evaluate({'a': -20, 'b': -70}); // a loud again: b's challenge lapses
    now = now.add(const Duration(milliseconds: 400));
    e.evaluate({'a': -30, 'b': -15}); // b louder again, but window restarted
    expect(e.activeSpeaker, 'a');
  });

  test('incumbent staying loudest cancels a pending challenge', () {
    final e = engine();
    e.evaluate({'a': -20, 'b': -70});
    e.evaluate({'a': -30, 'b': -15}); // b challenges
    e.evaluate({'a': -10, 'b': -40}); // a loudest again
    now = now.add(const Duration(seconds: 1));
    e.evaluate({'a': -30, 'b': -15}); // b challenges fresh, not yet held
    expect(e.activeSpeaker, 'a');
  });

  test('active drops to null when everyone falls silent', () {
    final e = engine();
    e.evaluate({'a': -20});
    expect(e.activeSpeaker, 'a');
    e.evaluate({'a': -80});
    expect(e.activeSpeaker, isNull);
  });

  test('respects custom config gains and floor', () {
    final e = engine(
      const DuckingConfig(
        activeGainDb: 3,
        duckedGainDb: -24,
        activationFloorDbfs: -40,
      ),
    );
    final gains = e.evaluate({'a': -35, 'b': -45}); // b below custom floor
    expect(e.activeSpeaker, 'a');
    expect(gains['a'], 3);
    expect(gains['b'], -24);
  });
}
