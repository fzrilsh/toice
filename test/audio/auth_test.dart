import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/auth.dart';
import 'package:toice/audio/signaling.dart';

/// In-memory bidirectional signaling: two ends cross-wired.
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

void main() {
  group('tripPinResponse', () {
    test('is deterministic and PIN-specific', () {
      expect(tripPinResponse('1234', 'abc'), tripPinResponse('1234', 'abc'));
      expect(
        tripPinResponse('1234', 'abc'),
        isNot(tripPinResponse('9999', 'abc')),
      );
      expect(
        tripPinResponse('1234', 'abc'),
        isNot(tripPinResponse('1234', 'xyz')),
      );
    });
  });

  group('PinChallenge', () {
    test('verifies the correct response and rejects a wrong PIN', () {
      final host = PinChallenge('1234', Random(1));
      final challenge = host.issueChallenge();
      expect(host.verify(tripPinResponse('9999', challenge)), isFalse);

      final host2 = PinChallenge('1234', Random(1));
      final c2 = host2.issueChallenge();
      expect(host2.verify(tripPinResponse('1234', c2)), isTrue);
    });

    test('a replayed response fails against a fresh challenge', () {
      final host = PinChallenge('1234', Random(2));
      final first = host.issueChallenge();
      final capturedMac = tripPinResponse('1234', first);
      expect(host.verify(capturedMac), isTrue);

      // Attacker replays the captured MAC against the next challenge.
      host.issueChallenge();
      expect(host.verify(capturedMac), isFalse);
    });
  });

  group('handshake over signaling', () {
    test('correct PIN authenticates end to end', () async {
      final (hostSig, clientSig) = LoopbackSignaling.pair();
      final client = respondToChallenge(clientSig, '4321');
      final ok = await authenticateClient(hostSig, '4321');
      await client;
      expect(ok, isTrue);
    });

    test('wrong PIN is rejected', () async {
      final (hostSig, clientSig) = LoopbackSignaling.pair();
      final client = respondToChallenge(clientSig, '0000');
      final ok = await authenticateClient(hostSig, '4321');
      await client;
      expect(ok, isFalse);
    });

    test('no response times out to false', () async {
      final (hostSig, _) = LoopbackSignaling.pair();
      final ok = await authenticateClient(
        hostSig,
        '4321',
        timeout: const Duration(milliseconds: 20),
      );
      expect(ok, isFalse);
    });
  });
}
