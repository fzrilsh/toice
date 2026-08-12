/// Device-backed [RtcPeer] wrapping `flutter_webrtc` (ADR-004/006).
///
/// Instantiates a real `RTCPeerConnection` with local-network ICE only (no
/// STUN/TURN, ADR-004) and Opus DTX. Only runs on a physical device; the pure
/// negotiation logic in [PeerLink]/[VoiceSession] is exercised by fakes in
/// tests instead.
library;

import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'rtc_peer.dart';
import 'signaling.dart';

// ponytail: ceiling = negotiation + single audio track, no mic capture, no
// host-side mixing, no DTX/ducking tuning yet. Add mic track wiring and the
// mixer when validating audio on-device (Phase 1 hardware / Phase 3).
class WebRtcPeer implements RtcPeer {
  WebRtcPeer._(this._pc);

  final RTCPeerConnection _pc;
  final _local = StreamController<Ice>.broadcast();
  final _states = StreamController<VoiceConnectionState>.broadcast();

  /// Local-network only: empty ICE server list, all peers share the hotspot LAN.
  static Future<WebRtcPeer> create() async {
    final pc = await createPeerConnection(const {'iceServers': []});
    final peer = WebRtcPeer._(pc);
    pc.onIceCandidate = (c) =>
        peer._local.add(Ice(c.candidate ?? '', c.sdpMid, c.sdpMLineIndex));
    pc.onConnectionState = (s) => peer._states.add(_mapState(s));
    return peer;
  }

  static VoiceConnectionState _mapState(RTCPeerConnectionState s) =>
      switch (s) {
        RTCPeerConnectionState.RTCPeerConnectionStateNew =>
          VoiceConnectionState.idle,
        RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
          VoiceConnectionState.connecting,
        RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          VoiceConnectionState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
          VoiceConnectionState.failed,
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
          VoiceConnectionState.failed,
        RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          VoiceConnectionState.closed,
      };

  @override
  Future<Sdp> createOffer() async {
    final o = await _pc.createOffer();
    return Sdp(o.type ?? 'offer', o.sdp ?? '');
  }

  @override
  Future<Sdp> createAnswer() async {
    final a = await _pc.createAnswer();
    return Sdp(a.type ?? 'answer', a.sdp ?? '');
  }

  @override
  Future<void> setLocalDescription(Sdp sdp) =>
      _pc.setLocalDescription(RTCSessionDescription(sdp.sdp, sdp.type));

  @override
  Future<void> setRemoteDescription(Sdp sdp) =>
      _pc.setRemoteDescription(RTCSessionDescription(sdp.sdp, sdp.type));

  @override
  Future<void> addIceCandidate(Ice ice) => _pc.addCandidate(
    RTCIceCandidate(ice.candidate, ice.sdpMid, ice.sdpMLineIndex),
  );

  @override
  Stream<Ice> get onLocalCandidate => _local.stream;

  @override
  Stream<VoiceConnectionState> get onStateChanged => _states.stream;

  @override
  Future<void> close() async {
    await _pc.close();
    await _local.close();
    await _states.close();
  }
}
