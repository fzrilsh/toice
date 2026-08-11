import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/peer_link.dart';
import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/audio/signaling.dart';
import 'package:toice/audio/voice_session.dart';

/// In-memory bidirectional signaling: two ends cross-wired so a [send] on one
/// surfaces on the other's [incoming]. Stands in for the on-device socket.
class LoopbackSignaling implements Signaling {
  LoopbackSignaling._(this._out, this._in);

  final StreamController<SignalMessage> _out;
  final StreamController<SignalMessage> _in;

  static (LoopbackSignaling, LoopbackSignaling) pair() {
    final a = StreamController<SignalMessage>.broadcast();
    final b = StreamController<SignalMessage>.broadcast();
    return (LoopbackSignaling._(a, b), LoopbackSignaling._(b, a));
  }

  @override
  Future<void> send(SignalMessage message) async => _out.add(message);

  @override
  Stream<SignalMessage> get incoming => _in.stream;

  @override
  Future<void> close() async {}
}

/// Fake peer: no libwebrtc. Produces canned SDP, emits one candidate, and lets
/// the test drive its connection state.
class FakePeer implements RtcPeer {
  final _cands = StreamController<Ice>.broadcast();
  final _states = StreamController<VoiceConnectionState>.broadcast();
  bool remoteSet = false;
  bool closed = false;

  @override
  Future<Sdp> createOffer() async => const Sdp('offer', 'fake-offer');

  @override
  Future<Sdp> createAnswer() async => const Sdp('answer', 'fake-answer');

  @override
  Future<void> setLocalDescription(Sdp sdp) async {}

  @override
  Future<void> setRemoteDescription(Sdp sdp) async => remoteSet = true;

  @override
  Future<void> addIceCandidate(Ice ice) async {}

  @override
  Stream<Ice> get onLocalCandidate => _cands.stream;

  @override
  Stream<VoiceConnectionState> get onStateChanged => _states.stream;

  void emitConnected() => _states.add(VoiceConnectionState.connected);

  @override
  Future<void> close() async {
    closed = true;
    await _cands.close();
    await _states.close();
  }
}

void main() {
  group('PeerLink negotiation', () {
    test('offer/answer completes across a loopback channel', () async {
      final (clientSig, hostSig) = LoopbackSignaling.pair();
      final clientPeer = FakePeer();
      final hostPeer = FakePeer();

      final host = PeerLink(
        peer: hostPeer,
        signaling: hostSig,
        initiator: false,
      );
      final client = PeerLink(
        peer: clientPeer,
        signaling: clientSig,
        initiator: true,
      );

      await host.connect();
      await client.connect();
      // Let the offer -> answer round trip drain.
      await Future<void>.delayed(Duration.zero);

      // Host consumed the client's offer; client consumed the host's answer.
      expect(hostPeer.remoteSet, isTrue);
      expect(clientPeer.remoteSet, isTrue);
      expect(client.state, VoiceConnectionState.connecting);

      await client.close();
      await host.close();
    });

    test('reaches connected when the peer reports connected', () async {
      final (clientSig, _) = LoopbackSignaling.pair();
      final peer = FakePeer();
      final link = PeerLink(peer: peer, signaling: clientSig, initiator: true);
      final connected = link.onStateChanged.firstWhere(
        (s) => s == VoiceConnectionState.connected,
      );

      await link.connect();
      peer.emitConnected();

      expect(await connected, VoiceConnectionState.connected);
      await link.close();
    });

    test('close is idempotent and frees the peer', () async {
      final (sig, _) = LoopbackSignaling.pair();
      final peer = FakePeer();
      final link = PeerLink(peer: peer, signaling: sig, initiator: true);

      await link.connect();
      await link.close();
      await link.close();

      expect(peer.closed, isTrue);
      expect(link.state, VoiceConnectionState.closed);
    });

    test('connect after close throws', () async {
      final (sig, _) = LoopbackSignaling.pair();
      final link = PeerLink(peer: FakePeer(), signaling: sig, initiator: true);
      await link.close();
      expect(link.connect, throwsStateError);
    });
  });

  group('VoiceSession roles', () {
    test('host accepts multiple clients', () async {
      final session = VoiceSession.host(FakePeer.new);
      await session.addPeer('c1', LoopbackSignaling.pair().$1);
      await session.addPeer('c2', LoopbackSignaling.pair().$1);

      expect(session.peerCount, 2);
      expect(session.role, SessionRole.host);
      await session.close();
      expect(session.peerCount, 0);
    });

    test('client links to exactly one host', () async {
      final session = VoiceSession.client(FakePeer.new);
      await session.connectToHost('host', LoopbackSignaling.pair().$1);

      expect(session.peerCount, 1);
      await expectLater(
        session.connectToHost('host2', LoopbackSignaling.pair().$1),
        throwsStateError,
      );
      await session.close();
    });

    test('client rejects addPeer, host rejects connectToHost', () async {
      final client = VoiceSession.client(FakePeer.new);
      final host = VoiceSession.host(FakePeer.new);
      await expectLater(
        client.addPeer('x', LoopbackSignaling.pair().$1),
        throwsStateError,
      );
      await expectLater(
        host.connectToHost('x', LoopbackSignaling.pair().$1),
        throwsStateError,
      );
    });

    test('duplicate peer id is rejected', () async {
      final session = VoiceSession.host(FakePeer.new);
      await session.addPeer('dup', LoopbackSignaling.pair().$1);
      await expectLater(
        session.addPeer('dup', LoopbackSignaling.pair().$1),
        throwsStateError,
      );
      await session.close();
    });

    test('removePeer drops the link', () async {
      final session = VoiceSession.host(FakePeer.new);
      await session.addPeer('c1', LoopbackSignaling.pair().$1);
      await session.removePeer('c1');
      expect(session.peerCount, 0);
      await session.close();
    });
  });
}
