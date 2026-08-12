import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/ducking.dart';
import 'package:toice/audio/speaker_levels.dart';

void main() {
  late DateTime now;
  late MockSpeakerLevelSource source;
  late ActiveSpeakerTracker tracker;

  setUp(() {
    now = DateTime(2026, 1, 1);
    source = MockSpeakerLevelSource();
    tracker = ActiveSpeakerTracker(
      source: source,
      engine: DuckingEngine(clock: () => now),
    );
  });

  tearDown(() async {
    await tracker.dispose();
    await source.close();
  });

  test('emits active speaker and gains for a scripted frame', () async {
    final actives = <String?>[];
    tracker.activeSpeaker.listen(actives.add);
    final gains = <Map<String, double>>[];
    tracker.gains.listen(gains.add);

    source.push([const SpeakerLevel('a', -20), const SpeakerLevel('b', -70)]);
    await Future<void>.delayed(Duration.zero);

    expect(actives, ['a']);
    expect(gains.single, {'a': 0, 'b': -18});
  });

  test('active speaker only switches after the hold time', () async {
    final actives = <String?>[];
    tracker.activeSpeaker.listen(actives.add);

    source.push([const SpeakerLevel('a', -20), const SpeakerLevel('b', -70)]);
    await Future<void>.delayed(Duration.zero);

    // b louder, but within hold time: no switch yet.
    now = now.add(const Duration(milliseconds: 200));
    source.push([const SpeakerLevel('a', -30), const SpeakerLevel('b', -15)]);
    await Future<void>.delayed(Duration.zero);

    // hold elapses, b still loudest: switch.
    now = now.add(const Duration(milliseconds: 400));
    source.push([const SpeakerLevel('a', -30), const SpeakerLevel('b', -15)]);
    await Future<void>.delayed(Duration.zero);

    expect(actives, ['a', 'b']); // deduped: only the two distinct actives
  });

  test('active speaker stream dedupes unchanged frames', () async {
    final actives = <String?>[];
    tracker.activeSpeaker.listen(actives.add);

    source.push([const SpeakerLevel('a', -20)]);
    source.push([const SpeakerLevel('a', -18)]);
    source.push([const SpeakerLevel('a', -22)]);
    await Future<void>.delayed(Duration.zero);

    expect(actives, ['a']); // 'a' emitted once, not per frame
  });

  test('dispose stops further emission', () async {
    final actives = <String?>[];
    tracker.activeSpeaker.listen(actives.add);
    await tracker.dispose();

    source.push([const SpeakerLevel('a', -20)]);
    await Future<void>.delayed(Duration.zero);

    expect(actives, isEmpty);
  });
}
