/// WebRTC negotiation state machine for one peer link (ADR-004).
///
/// Pure orchestration over [RtcPeer] + [Signaling]: no `flutter_webrtc` import,
/// so it runs under `flutter test` with fakes. Convention: the joining client
/// is the offerer, the host answers (mirrors the star topology, ADR-001).
library;

// Named params cannot be private, so private deps are assigned from public
// aliases in the initializer list rather than via initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'rtc_peer.dart';
import 'signaling.dart';

/// Drives SDP offer/answer + ICE trickle for a single connection and exposes
/// its [VoiceConnectionState]. Create one per link (client: one to the host;
/// host: one per client).
class PeerLink {
  PeerLink({
    required RtcPeer peer,
    required Signaling signaling,
    required this.initiator,
  }) : _peer = peer,
       _signaling = signaling;

  final RtcPeer _peer;
  final Signaling _signaling;

  /// True on the offering side (the joining client), false on the answerer
  /// (the host).
  final bool initiator;

  final _state = StreamController<VoiceConnectionState>.broadcast();
  VoiceConnectionState _current = VoiceConnectionState.idle;
  StreamSubscription<SignalMessage>? _incomingSub;
  StreamSubscription<Ice>? _candidateSub;
  StreamSubscription<VoiceConnectionState>? _peerStateSub;
  bool _closed = false;

  VoiceConnectionState get state => _current;
  Stream<VoiceConnectionState> get onStateChanged => _state.stream;

  void _emit(VoiceConnectionState s) {
    if (_closed || s == _current) return;
    _current = s;
    _state.add(s);
  }

  /// Begin negotiation. Wires signaling and peer-state streams first (so no
  /// early message or candidate is dropped), then, if [initiator], sends the
  /// opening offer.
  Future<void> connect() async {
    if (_closed) {
      throw StateError('PeerLink.connect() after close()');
    }
    _emit(VoiceConnectionState.connecting);

    _peerStateSub = _peer.onStateChanged.listen(_emit);
    _candidateSub = _peer.onLocalCandidate.listen(
      (ice) => _signaling.send(CandidateMessage(ice)),
    );
    _incomingSub = _signaling.incoming.listen(_onSignal);

    if (initiator) {
      final offer = await _peer.createOffer();
      await _peer.setLocalDescription(offer);
      await _signaling.send(OfferMessage(offer));
    }
  }

  Future<void> _onSignal(SignalMessage msg) async {
    switch (msg) {
      case OfferMessage(:final sdp):
        // Answerer path: remote offer -> local answer.
        await _peer.setRemoteDescription(sdp);
        final answer = await _peer.createAnswer();
        await _peer.setLocalDescription(answer);
        await _signaling.send(AnswerMessage(answer));
      case AnswerMessage(:final sdp):
        await _peer.setRemoteDescription(sdp);
      case CandidateMessage(:final ice):
        await _peer.addIceCandidate(ice);
      case ChallengeMessage() || AuthResponseMessage():
        // Trip PIN handshake (Phase 4.5) runs before the link is created, over
        // the same channel; ignore any stray auth frame here.
        break;
    }
  }

  /// Tear down the link. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _incomingSub?.cancel();
    await _candidateSub?.cancel();
    await _peerStateSub?.cancel();
    await _peer.close();
    await _signaling.close();
    if (_current != VoiceConnectionState.closed) {
      _current = VoiceConnectionState.closed;
      _state.add(VoiceConnectionState.closed);
    }
    await _state.close();
  }
}
