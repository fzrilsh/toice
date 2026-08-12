import 'package:flutter_test/flutter_test.dart';
import 'package:toice/election/broadcast.dart';
import 'package:toice/election/election_daemon.dart';
import 'package:toice/election/handoff.dart';
import 'package:toice/native_bridge/native_bridge.g.dart' show ThermalState;

/// Records what the daemon emitted; lets a test hand-deliver replies.
class FakeChannel implements ElectionChannel {
  final broadcasts = <ElectionBroadcast>[];
  final signals = <ElectionSignal>[];
  @override
  void emit(ElectionBroadcast b) => broadcasts.add(b);
  @override
  void emitSignal(ElectionSignal s) => signals.add(s);
}

class FakeSwitcher implements HostSwitcher {
  int becameHost = 0;
  int stopped = 0;
  @override
  Future<void> becomeHost() async => becameHost++;
  @override
  Future<void> stopHosting() async => stopped++;
}

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
  late DateTime now;
  late FakeChannel channel;
  late FakeSwitcher switcher;

  ElectionDaemon daemon(String id) => ElectionDaemon(
    deviceId: id,
    channel: channel,
    switcher: switcher,
    clock: () => now,
    margin: 10,
    hysteresisDuration: const Duration(seconds: 5),
    ackTimeout: const Duration(seconds: 2),
    staleAfter: const Duration(seconds: 6),
  );

  setUp(() {
    now = DateTime(2026, 1, 1);
    channel = FakeChannel();
    switcher = FakeSwitcher();
  });

  test('self broadcast is published on the channel', () {
    final d = daemon('me');
    d.broadcastSelf(bc('me', worstDbm: -50));
    expect(channel.broadcasts.single.senderId, 'me');
  });

  test('this device wins and takes over via intent/ack handoff', () async {
    final d = daemon('me');
    d.broadcastSelf(bc('me', worstDbm: -45, battery: 95));
    d.onBroadcast(bc('other', worstDbm: -80, battery: 30));

    // Sustained lead must hold through the hysteresis window before switching.
    await d.tick();
    expect(d.isHost, isFalse);
    expect(channel.signals, isEmpty);

    now = now.add(const Duration(seconds: 5));
    await d.tick();
    // Won: broadcast intent, awaiting the one peer's ack.
    expect(channel.signals.whereType<HandoffIntent>(), hasLength(1));
    expect(d.handoffState, HandoffState.awaitingAcks);
    expect(switcher.becameHost, 0);

    await d.onSignal(const HandoffAck('other', 'me'));
    expect(switcher.becameHost, 1);
    expect(d.isHost, isTrue);
    expect(d.handoffState, HandoffState.stable);
  });

  test('ack timeout still completes the takeover', () async {
    final d = daemon('me');
    d.broadcastSelf(bc('me', worstDbm: -45));
    d.onBroadcast(bc('other', worstDbm: -85));

    await d.tick(); // primes the hysteresis timer (first evaluate never fires)
    now = now.add(const Duration(seconds: 5));
    await d.tick(); // wins, broadcasts intent
    expect(d.handoffState, HandoffState.awaitingAcks);

    now = now.add(const Duration(seconds: 2)); // ack window elapses
    await d.tick();
    expect(switcher.becameHost, 1);
    expect(d.isHost, isTrue);
  });

  test('a peer winning is recorded, and its intent is acked', () async {
    final d = daemon('me');
    d.broadcastSelf(bc('me', worstDbm: -85));
    d.onBroadcast(bc('strong', worstDbm: -40, battery: 99));

    await d.tick(); // primes the hysteresis timer
    now = now.add(const Duration(seconds: 5));
    await d.tick();
    expect(d.currentHost, 'strong');
    expect(switcher.becameHost, 0);

    // The peer announces its takeover: we ack and never contest.
    await d.onSignal(const HandoffIntent('strong'));
    expect(channel.signals.whereType<HandoffAck>().single.toHost, 'strong');
  });

  test('stale peers are pruned and stop counting as candidates', () async {
    final d = daemon('me');
    d.onBroadcast(bc('ghost', worstDbm: -40, battery: 99));

    now = now.add(const Duration(seconds: 7)); // beyond staleAfter
    d.broadcastSelf(bc('me', worstDbm: -80, battery: 40));
    await d.tick();
    await d.onSignal(const HandoffAck('ghost', 'me')); // no effect, ghost gone

    // With the strong ghost pruned, only 'me' remains, so 'me' can win.
    now = now.add(const Duration(seconds: 5));
    await d.tick();
    expect(d.isHost, isTrue);
  });

  test('all-iOS field: nobody host-capable, no host elected', () async {
    final d = daemon('me-ios');
    d.broadcastSelf(bc('me-ios', worstDbm: -45, hostCapable: false));
    d.onBroadcast(bc('other-ios', worstDbm: -50, hostCapable: false));

    now = now.add(const Duration(seconds: 5));
    await d.tick();
    expect(d.currentHost, isNull);
    expect(switcher.becameHost, 0);
  });
}
