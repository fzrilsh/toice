/// Minimal peer-connection boundary (ADR-004).
///
/// `flutter_webrtc`'s `RTCPeerConnection` only instantiates on a device, so
/// [VoiceSession] depends on this narrow interface instead. The real
/// implementation wraps `flutter_webrtc` (device); tests use a fake.
library;

import 'signaling.dart';

/// Lifecycle of a single peer link, mapped from `RTCPeerConnectionState`.
enum VoiceConnectionState { idle, connecting, connected, failed, closed }

/// The subset of `RTCPeerConnection` the session needs. Media (mic tracks,
/// host-side mixing) is added on the device impl; this interface stays about
/// negotiation and connection state so it is fully unit-testable.
abstract class RtcPeer {
  Future<Sdp> createOffer();
  Future<Sdp> createAnswer();
  Future<void> setLocalDescription(Sdp sdp);
  Future<void> setRemoteDescription(Sdp sdp);
  Future<void> addIceCandidate(Ice ice);

  /// Local ICE candidates to forward to the peer over [Signaling].
  Stream<Ice> get onLocalCandidate;

  /// Connection-state transitions from the underlying peer connection.
  Stream<VoiceConnectionState> get onStateChanged;

  Future<void> close();
}

/// Creates a fresh peer connection per link. Real factory injects local-network
/// ICE config (no STUN/TURN, ADR-004); the fake ignores it.
typedef RtcPeerFactory = RtcPeer Function();
