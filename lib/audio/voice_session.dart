/// Voice session over the hotspot star topology (ADR-001/004).
///
/// A [VoiceSession] is either a host (one [PeerLink] per joining client,
/// host-side mixing lands on the device impl) or a client (a single link to the
/// host). Pure orchestration over [PeerLink]s; unit-testable with fake peers
/// and loopback signaling.
library;

import 'dart:async';

import 'peer_link.dart';
import 'rtc_peer.dart';
import 'signaling.dart';

enum SessionRole { host, client }

class VoiceSession {
  VoiceSession._(this.role, this._newPeer);

  /// Host: accepts multiple clients via [addPeer].
  factory VoiceSession.host(RtcPeerFactory newPeer) =>
      VoiceSession._(SessionRole.host, newPeer);

  /// Client: connect to the host with [connectToHost]. A client links to
  /// exactly one host, so a second call throws.
  factory VoiceSession.client(RtcPeerFactory newPeer) =>
      VoiceSession._(SessionRole.client, newPeer);

  final SessionRole role;
  final RtcPeerFactory _newPeer;
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
  Future<PeerLink> addPeer(String peerId, Signaling signaling) async {
    if (role != SessionRole.host) {
      throw StateError('addPeer is host-only');
    }
    final link = _link(peerId, signaling, initiator: false);
    await link.connect();
    return link;
  }

  /// Client: connect to the host over [signaling]. The client is the offerer.
  Future<PeerLink> connectToHost(String hostId, Signaling signaling) async {
    if (role != SessionRole.client) {
      throw StateError('connectToHost is client-only');
    }
    if (_links.isNotEmpty) {
      throw StateError('a client links to exactly one host');
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
