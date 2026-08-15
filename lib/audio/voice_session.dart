/// Voice session over the hotspot star topology (ADR-001/004).
///
/// A [VoiceSession] is either a host (one [PeerLink] per joining client,
/// host-side mixing lands on the device impl) or a client (a single link to the
/// host). Pure orchestration over [PeerLink]s; unit-testable with fake peers
/// and loopback signaling.
library;

import 'dart:async';

import 'auth.dart';
import 'peer_link.dart';
import 'rtc_peer.dart';
import 'signaling.dart';

enum SessionRole { host, client }

/// Thrown when a joining client fails the Trip PIN handshake (Phase 4.5). The
/// peer is never linked, so it never reaches the roster.
class AuthFailedException implements Exception {
  const AuthFailedException(this.peerId);
  final String peerId;
  @override
  String toString() => 'peer $peerId failed Trip PIN auth';
}

class VoiceSession {
  VoiceSession._(this.role, this._newPeer, {this.tripPin});

  /// Host: accepts multiple clients via [addPeer]. When [tripPin] is set, each
  /// joining client must pass the Trip PIN handshake before it is linked.
  factory VoiceSession.host(RtcPeerFactory newPeer, {String? tripPin}) =>
      VoiceSession._(SessionRole.host, newPeer, tripPin: tripPin);

  /// Client: connect to the host with [connectToHost]. A client links to
  /// exactly one host, so a second call throws.
  factory VoiceSession.client(RtcPeerFactory newPeer) =>
      VoiceSession._(SessionRole.client, newPeer);

  final SessionRole role;
  final RtcPeerFactory _newPeer;

  /// Shared secret for the app-layer client handshake (Phase 4.5); null skips
  /// auth (a scanned join before the rider enters the PIN, or legacy tests).
  final String? tripPin;
  final _links = <String, PeerLink>{};
  final _subs = <String, StreamSubscription<VoiceConnectionState>>{};
  final _changes =
      StreamController<Map<String, VoiceConnectionState>>.broadcast();

  /// Live view of per-peer connection state, keyed by peer id.
  Map<String, VoiceConnectionState> get connections => {
    for (final e in _links.entries) e.key: e.value.state,
  };

  /// Emits the [connections] snapshot whenever any link changes state or a peer
  /// is added/removed. Drives a reactive UI without polling.
  Stream<Map<String, VoiceConnectionState>> get connectionChanges =>
      _changes.stream;

  int get peerCount => _links.length;

  void _emitChange() {
    if (!_changes.isClosed) _changes.add(connections);
  }

  /// Host: register a joining client. [signaling] is the channel to that one
  /// client; the host is the answerer (it waits for the client's offer).
  ///
  /// If [tripPin] is set, the client must pass the Trip PIN handshake first
  /// (Phase 4.5); a client that fails is never linked and throws
  /// [AuthFailedException], so an unauthenticated peer never enters the roster.
  Future<PeerLink> addPeer(String peerId, Signaling signaling) async {
    if (role != SessionRole.host) {
      throw StateError('addPeer is host-only');
    }
    final pin = tripPin;
    if (pin != null && !await authenticateClient(signaling, pin)) {
      throw AuthFailedException(peerId);
    }
    final link = _link(peerId, signaling, initiator: false);
    await link.connect();
    return link;
  }

  /// Client: connect to the host over [signaling]. The client is the offerer.
  /// When [tripPin] is given, answer the host's Trip PIN challenge first
  /// (Phase 4.5) so the host admits this client.
  Future<PeerLink> connectToHost(
    String hostId,
    Signaling signaling, {
    String? tripPin,
  }) async {
    if (role != SessionRole.client) {
      throw StateError('connectToHost is client-only');
    }
    if (_links.isNotEmpty) {
      throw StateError('a client links to exactly one host');
    }
    if (tripPin != null) {
      await respondToChallenge(signaling, tripPin);
    }
    final link = _link(hostId, signaling, initiator: true);
    await link.connect();
    return link;
  }

  PeerLink _link(
    String peerId,
    Signaling signaling, {
    required bool initiator,
  }) {
    if (_links.containsKey(peerId)) {
      throw StateError('peer $peerId already linked');
    }
    final link = PeerLink(
      peer: _newPeer(),
      signaling: signaling,
      initiator: initiator,
    );
    _links[peerId] = link;
    // Mirror each link's state into the aggregate stream, and drop the link
    // once it closes so peerCount reflects live peers.
    _subs[peerId] = link.onStateChanged.listen((s) {
      if (s == VoiceConnectionState.closed) {
        _links.remove(peerId);
        _subs.remove(peerId)?.cancel();
      }
      _emitChange();
    });
    _emitChange();
    return link;
  }

  /// Close and forget one peer.
  Future<void> removePeer(String peerId) async {
    final link = _links.remove(peerId);
    await _subs.remove(peerId)?.cancel();
    await link?.close();
    _emitChange();
  }

  /// Close every link and end the session.
  Future<void> close() async {
    final links = List<PeerLink>.of(_links.values);
    _links.clear();
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    await Future.wait(links.map((l) => l.close()));
    _emitChange();
    await _changes.close();
  }
}
