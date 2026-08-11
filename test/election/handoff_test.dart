import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/handoff.dart';

void main() {
  late DateTime now;
  HandoffMachine machine(Set<String> ackers) => HandoffMachine(
    newHostId: 'newhost',
    expectedAckers: ackers,
    ackTimeout: const Duration(seconds: 2),
    clock: () => now,
  );

  setUp(() => now = DateTime(2026, 1, 1));

  test('happy path: intent, all acks, switch, complete', () {
    final m = machine({'a', 'b'});

    final begin = m.begin();
    expect(begin.state, HandoffState.awaitingAcks);
    expect(begin.action, HandoffAction.broadcastIntent);

    expect(m.onAck('a').action, HandoffAction.none);
    expect(m.pendingAckers, {'b'});

    final last = m.onAck('b');
    expect(last.state, HandoffState.switching);
    expect(last.action, HandoffAction.performSwitch);

    final done = m.onSwitchComplete();
    expect(done.state, HandoffState.stable);
    expect(done.action, HandoffAction.complete);
  });

  test('no expected ackers: switch immediately on begin', () {
    final m = machine({});
    final step = m.begin();
    expect(step.state, HandoffState.switching);
    expect(step.action, HandoffAction.performSwitch);
  });

  test('ack timeout: unilateral takeover', () {
    final m = machine({'a', 'b'});
    m.begin();
    m.onAck('a'); // only one ack arrives

    now = now.add(const Duration(seconds: 1));
    expect(m.onTick().action, HandoffAction.none); // window not yet elapsed

    now = now.add(const Duration(seconds: 1));
    final t = m.onTick();
    expect(t.state, HandoffState.switching);
    expect(t.action, HandoffAction.performSwitch);
  });

  test('acks from unexpected peers are ignored', () {
    final m = machine({'a'});
    m.begin();
    expect(m.onAck('stranger').action, HandoffAction.none);
    expect(m.pendingAckers, {'a'});
  });

  test('begin is idempotent while in flight', () {
    final m = machine({'a'});
    m.begin();
    final again = m.begin();
    expect(again.action, HandoffAction.none);
    expect(again.state, HandoffState.awaitingAcks);
  });

  test('single-host invariant: switch is emitted exactly once', () {
    final m = machine({'a'});
    m.begin();
    expect(m.onAck('a').action, HandoffAction.performSwitch);
    // A late duplicate ack or tick must not re-emit performSwitch.
    expect(m.onAck('a').action, HandoffAction.none);
    expect(m.onTick().action, HandoffAction.none);
  });

  test('stray onSwitchComplete before switching is ignored', () {
    final m = machine({'a'});
    m.begin();
    expect(m.onSwitchComplete().action, HandoffAction.none);
    expect(m.state, HandoffState.awaitingAcks);
  });
}
