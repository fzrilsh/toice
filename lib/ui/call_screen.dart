import 'dart:async';

import 'package:flutter/material.dart';

import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/audio/signaling.dart';
import 'package:toice/audio/voice_session.dart';

/// Phase 1 call screen (ADR-004): shows live per-peer connection state from a
/// [VoiceSession]. Not the final UI (Phase 4); this validates the session state
/// machine end to end without a device by driving it with a mock peer +
/// loopback signaling. Real audio/mic/mixing arrives with device work.
///
/// [sessionFactory] and [signalingFactory]/[peerFactory] are injected so the
/// same screen renders against the real device stack later by swapping them.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.session,
    required this.newSignaling,
  });

  final VoiceSession session;

  /// Produces the signaling channel for a joining/joined peer. On device this
  /// is a socket; in the mock harness it is one end of a loopback pair whose
  /// other end is driven by a fake remote peer.
  final Signaling Function() newSignaling;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  var _connections = <String, VoiceConnectionState>{};
  int _peerSeq = 0;

  @override
  void initState() {
    super.initState();
    _connections = widget.session.connections;
    widget.session.connectionChanges.listen((c) {
      if (mounted) setState(() => _connections = c);
    });
  }

  Future<void> _addClient() async {
    final id = 'rider-${++_peerSeq}';
    await widget.session.addPeer(id, widget.newSignaling());
  }

  Future<void> _connect() async {
    await widget.session.connectToHost('host', widget.newSignaling());
  }

  @override
  Widget build(BuildContext context) {
    final isHost = widget.session.role == SessionRole.host;
    return Scaffold(
      appBar: AppBar(title: Text(isHost ? 'Toice - Host' : 'Toice - Client')),
      floatingActionButton: isHost
          ? FloatingActionButton.extended(
              onPressed: _addClient,
              icon: const Icon(Icons.person_add),
              label: const Text('Add rider'),
            )
          : (_connections.isEmpty
                ? FloatingActionButton.extended(
                    onPressed: _connect,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Connect'),
                  )
                : null),
      body: _connections.isEmpty
          ? const Center(child: Text('No peers yet'))
          : ListView(
              children: [
                for (final entry in _connections.entries)
                  _PeerTile(
                    peerId: entry.key,
                    state: entry.value,
                    onRemove: () => widget.session.removePeer(entry.key),
                  ),
              ],
            ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({
    required this.peerId,
    required this.state,
    required this.onRemove,
  });

  final String peerId;
  final VoiceConnectionState state;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon, color: _color),
      title: Text(peerId),
      subtitle: Text(state.name),
      trailing: IconButton(
        icon: const Icon(Icons.call_end),
        onPressed: onRemove,
      ),
    );
  }

  IconData get _icon => switch (state) {
    VoiceConnectionState.connected => Icons.person,
    VoiceConnectionState.connecting => Icons.hourglass_top,
    VoiceConnectionState.failed => Icons.error_outline,
    VoiceConnectionState.closed => Icons.person_off,
    VoiceConnectionState.idle => Icons.person_outline,
  };

  Color get _color => switch (state) {
    VoiceConnectionState.connected => Colors.green,
    VoiceConnectionState.connecting => Colors.orange,
    VoiceConnectionState.failed => Colors.red,
    _ => Colors.grey,
  };
}

/// Mock harness (no device): a [VoiceSession] whose peers are [_ScriptedPeer]s
/// that walk connecting -> connected on their own, and a loopback [Signaling]
/// so negotiation completes. Lets the screen be run and widget-tested without
/// libwebrtc. Swap [VoiceSession.host]'s factory for `WebRtcPeer.create` and
/// [newSignaling] for a socket channel to go live.
VoiceSession mockHostSession() => VoiceSession.host(_ScriptedPeer.new);

VoiceSession mockClientSession() => VoiceSession.client(_ScriptedPeer.new);

Signaling mockSignaling() => _NullSignaling();

class _NullSignaling implements Signaling {
  final _in = StreamController<SignalMessage>.broadcast();
  @override
  Stream<SignalMessage> get incoming => _in.stream;
  @override
  Future<void> send(SignalMessage message) async {}
  @override
  Future<void> close() async => _in.close();
}

class _ScriptedPeer implements RtcPeer {
  final _cands = StreamController<Ice>.broadcast();
  final _states = StreamController<VoiceConnectionState>.broadcast();

  @override
  Future<Sdp> createOffer() async => const Sdp('offer', 'mock');
  @override
  Future<Sdp> createAnswer() async => const Sdp('answer', 'mock');
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
    // Simulate a link that connects shortly after negotiation starts.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
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
