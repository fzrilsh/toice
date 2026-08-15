/// App-layer Trip PIN authentication over the signaling channel (Phase 4.5).
///
/// Option B keeps the PIN out of the WiFi QR, so anyone who merely scanned the
/// join QR is on the LAN but does not know the PIN. Before a client is admitted
/// to the voice session the host runs a challenge/response:
///
///   1. host -> [ChallengeMessage] with a fresh random nonce
///   2. client -> [AuthResponseMessage] with HMAC-SHA256(tripPin, challenge)
///   3. host recomputes the same HMAC and admits the client only on a match
///
/// The PIN is never sent over the wire, and each challenge is single-use and
/// random, so a captured response cannot be replayed against a new challenge.
///
/// ponytail: HMAC over the PIN, not a full PAKE. A 4-6 digit PIN is
/// low-entropy, so this resists passive capture and replay but not an active
/// on-LAN attacker brute-forcing offline. Upgrade to SPAKE2/J-PAKE if the
/// threat model tightens; the message pair stays the same shape.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'signaling.dart';

/// Compute the handshake answer for [tripPin] against [challenge].
String tripPinResponse(String tripPin, String challenge) {
  final mac = Hmac(sha256, utf8.encode(tripPin));
  return mac.convert(utf8.encode(challenge)).toString();
}

/// Host side of the handshake: issue one challenge, then verify one response.
///
/// Single-use: [verify] only ever accepts the response to the exact challenge
/// [issueChallenge] produced, so a replayed answer from an earlier challenge
/// fails.
class PinChallenge {
  PinChallenge(this._tripPin, [Random? rng]) : _rng = rng ?? Random.secure();

  final String _tripPin;
  final Random _rng;
  String? _challenge;

  /// Produce a fresh random challenge to send to the joining client.
  String issueChallenge() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return _challenge = base64Url.encode(bytes);
  }

  /// True only if [mac] is the correct response to the outstanding challenge.
  /// Consumes the challenge, so a second call (a replay) always fails until a
  /// new challenge is issued.
  bool verify(String mac) {
    final challenge = _challenge;
    _challenge = null;
    if (challenge == null) return false;
    return _constantTimeEquals(mac, tripPinResponse(_tripPin, challenge));
  }
}

/// Compare two hex MAC strings without early-exit timing leaks.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Host side over a live [signaling] channel: challenge the joining client and
/// resolve true only if it answers with the correct HMAC before [timeout].
///
/// Wire this before admitting a peer to the [VoiceSession]: an unauthenticated
/// client stays pending and never enters the roster.
Future<bool> authenticateClient(
  Signaling signaling,
  String tripPin, {
  Duration timeout = const Duration(seconds: 15),
  Random? rng,
}) async {
  final challenger = PinChallenge(tripPin, rng);
  final answered = signaling.incoming
      .where((m) => m is AuthResponseMessage)
      .cast<AuthResponseMessage>()
      .map((m) => challenger.verify(m.mac))
      .first
      .timeout(timeout, onTimeout: () => false);
  await signaling.send(ChallengeMessage(challenger.issueChallenge()));
  return answered;
}

/// Client side over a live [signaling] channel: answer the host's challenge
/// with HMAC([tripPin]). Completes once one challenge has been answered.
Future<void> respondToChallenge(Signaling signaling, String tripPin) async {
  final challenge = await signaling.incoming
      .where((m) => m is ChallengeMessage)
      .cast<ChallengeMessage>()
      .map((m) => m.challenge)
      .first;
  await signaling.send(
    AuthResponseMessage(tripPinResponse(tripPin, challenge)),
  );
}
