import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toice/app/session_store.dart';
import 'package:toice/audio/ducking.dart';
import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/audio/signaling.dart';
import 'package:toice/audio/speaker_levels.dart';
import 'package:toice/audio/voice_session.dart';
import 'package:toice/election/handoff.dart';

/// Fake peer that reports connected right after negotiation, no real media.
class _FakePeer implements RtcPeer {
  final _cands = StreamController<Ice>.broadcast();
  final _states = StreamController<VoiceConnectionState>.broadcast();

  @override
  Future<Sdp> createOffer() async => const Sdp('offer', 'x');
  @override
  Future<Sdp> createAnswer() async => const Sdp('answer', 'x');
  @override
  Future<void> setLocalDescription(Sdp sdp) async {}
  @override
  Future<void> setRemoteDescription(Sdp sdp) async {}
  @override
  Future<void> addIceCandidate(Ice ice) async {}
  @override
  Stream<Ice> get onLocalCandidate => _cands.stream;
  @override
  Stream<VoiceConnectionState> get onStateChanged {
    scheduleMicrotask(() {
      if (!_states.isClosed) _states.add(VoiceConnectionState.connected);
    });
    return _states.stream;
  }

  @override
  Future<void> close() async {
    await _cands.close();
    await _states.close();
  }
}

class _NullSignaling implements Signaling {
  final _in = StreamController<SignalMessage>.broadcast();
  @override
  Stream<SignalMessage> get incoming => _in.stream;
  @override
  Future<void> send(SignalMessage message) async {}
  @override
  Future<void> close() async => _in.close();
}

void main() {
  late DateTime now;
  late VoiceSession session;
  late MockSpeakerLevelSource source;
  late ActiveSpeakerTracker tracker;
  late SessionStore store;

  setUp(() {
    now = DateTime(2026, 1, 1);
    session = VoiceSession.host(_FakePeer.new);
    source = MockSpeakerLevelSource();
    tracker = ActiveSpeakerTracker(
      source: source,
      engine: DuckingEngine(clock: () => now),
    );
    store = SessionStore(session: session, speaker: tracker);
  });

  tearDown(() async {
    store.dispose();
    await tracker.dispose();
    await source.close();
    await session.close();
  });

  test('riders reflect connection state and fire listeners', () async {
    var notified = 0;
    store.addListener(() => notified++);

    await session.addPeer('rider-1', _NullSignaling());
    await Future<void>.delayed(Duration.zero); // let the fake reach connected

    expect(store.riders, hasLength(1));
    expect(store.riders.single.peerId, 'rider-1');
    expect(store.riders.single.connection, VoiceConnectionState.connected);
    expect(notified, greaterThan(0));
  });

  test('active speaker marks the matching rider as speaking', () async {
    await session.addPeer('rider-1', _NullSignaling());
    await session.addPeer('rider-2', _NullSignaling());
    await Future<void>.delayed(Duration.zero);

    source.push([
      const SpeakerLevel('rider-1', -20),
      const SpeakerLevel('rider-2', -70),
    ]);
    await Future<void>.delayed(Duration.zero);

    final speaking = store.riders.where((r) => r.isSpeaking).toList();
    expect(speaking, hasLength(1));
    expect(speaking.single.peerId, 'rider-1');
  });

  test('updateHostStatus marks the host and notifies', () async {
    await session.addPeer('rider-1', _NullSignaling());
    await Future<void>.delayed(Duration.zero);

    var notified = 0;
    store.addListener(() => notified++);
    store.updateHostStatus(
      currentHost: 'rider-1',
      handoffState: HandoffState.switching,
    );

    expect(store.currentHost, 'rider-1');
    expect(store.handoffState, HandoffState.switching);
    expect(store.riders.single.isHost, isTrue);
    expect(notified, 1);
  });

  test('updateHostStatus is a no-op when nothing changed', () {
    var notified = 0;
    store.addListener(() => notified++);
    store.updateHostStatus(
      currentHost: null,
      handoffState: HandoffState.stable,
    );
    expect(notified, 0);
  });
}
