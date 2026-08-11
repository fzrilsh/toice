/// Signaling boundary for the WebRTC voice layer (ADR-004).
///
/// WebRTC needs a side channel to exchange SDP and ICE before media flows. On
/// the hotspot LAN that channel is a socket to the host (Phase 1 device work);
/// in unit tests it is an in-memory loopback. [VoiceSession] talks only to this
/// interface, so the negotiation logic runs without a device.
library;

/// Session description (SDP), transport-agnostic mirror of
/// `RTCSessionDescription` so this layer needs no `flutter_webrtc` import.
class Sdp {
  const Sdp(this.type, this.sdp);

  /// "offer" or "answer".
  final String type;
  final String sdp;
}

/// ICE candidate, transport-agnostic mirror of `RTCIceCandidate`.
class Ice {
  const Ice(this.candidate, this.sdpMid, this.sdpMLineIndex);

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

/// One message over the signaling channel.
sealed class SignalMessage {
  const SignalMessage();
}

class OfferMessage extends SignalMessage {
  const OfferMessage(this.sdp);
  final Sdp sdp;
}

class AnswerMessage extends SignalMessage {
  const AnswerMessage(this.sdp);
  final Sdp sdp;
}

class CandidateMessage extends SignalMessage {
  const CandidateMessage(this.ice);
  final Ice ice;
}

/// A bidirectional signaling channel between one peer and its counterpart.
abstract class Signaling {
  /// Send a message to the other peer.
  Future<void> send(SignalMessage message);

  /// Messages arriving from the other peer.
  Stream<SignalMessage> get incoming;

  /// Stop delivering and release resources.
  Future<void> close();
}
