import 'dart:async';

import 'package:flutter/material.dart';

import 'package:toice/app/session_store.dart';
import 'package:toice/audio/ducking.dart';
import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/audio/signaling.dart';
import 'package:toice/audio/speaker_levels.dart';
import 'package:toice/audio/voice_session.dart';

/// Phase 1/3 call screen (ADR-004): renders the live roster from a
/// [SessionStore] that binds connection state and the active speaker. Not the
/// final UI (Phase 4); it validates the session + audio decision layers end to
/// end without a device, driven by a mock peer, loopback signaling, and a
/// scripted speaker-level source. Real audio/mic/mixing arrives with device
/// work.
///
/// [session], [newSignaling], and [speakerSource] are injected so the same
/// screen renders against the real device stack later by swapping them.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.session,
    required this.newSignaling,
    required this.speakerSource,
  });

  final VoiceSession session;

  /// Produces the signaling channel for a joining/joined peer (socket on
  /// device, loopback in the mock harness).
  final Signaling Function() newSignaling;

  /// Per-stream audio metering (WebRTC stats on device, scripted mock here).
  final SpeakerLevelSource speakerSource;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final ActiveSpeakerTracker _tracker;
  late final SessionStore _store;
  int _peerSeq = 0;

  @override
  void initState() {
    super.initState();
    _tracker = ActiveSpeakerTracker(
      source: widget.speakerSource,
      engine: DuckingEngine(clock: DateTime.now),
    );
    _store = SessionStore(session: widget.session, speaker: _tracker);
  }

  @override
  void dispose() {
    _store.dispose();
    _tracker.dispose();
    super.dispose();
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
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final riders = _store.riders;
        return Scaffold(
          appBar: AppBar(
            title: Text(isHost ? 'Toice - Host' : 'Toice - Client'),
          ),
          floatingActionButton: isHost
              ? FloatingActionButton.extended(
                  onPressed: _addClient,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add rider'),
                )
              : (riders.isEmpty
                    ? FloatingActionButton.extended(
                        onPressed: _connect,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Connect'),
                      )
                    : null),
          body: riders.isEmpty
              ? const Center(child: Text('No peers yet'))
              : ListView(
                  children: [
                    for (final rider in riders)
                      _PeerTile(
                        rider: rider,
                        onRemove: () => widget.session.removePeer(rider.peerId),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.rider, required this.onRemove});

  final RiderView rider;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon, color: _color),
      title: Row(
        children: [
          Text(rider.peerId),
          if (rider.isHost) ...[
            const SizedBox(width: 8),
            const Icon(Icons.star, size: 16, color: Colors.amber),
          ],
          if (rider.isSpeaking) ...[
            const SizedBox(width: 8),
            const Icon(Icons.graphic_eq, size: 16, color: Colors.green),
          ],
        ],
      ),
      subtitle: Text(rider.connection.name),
      trailing: IconButton(
        icon: const Icon(Icons.call_end),
        onPressed: onRemove,
      ),
    );
  }

  IconData get _icon => switch (rider.connection) {
    VoiceConnectionState.connected => Icons.person,
    VoiceConnectionState.connecting => Icons.hourglass_top,
    VoiceConnectionState.failed => Icons.error_outline,
    VoiceConnectionState.closed => Icons.person_off,
    VoiceConnectionState.idle => Icons.person_outline,
  };

  Color get _color => switch (rider.connection) {
    VoiceConnectionState.connected => Colors.green,
    VoiceConnectionState.connecting => Colors.orange,
    VoiceConnectionState.failed => Colors.red,
    _ => Colors.grey,
  };
}

/// Mock harness (no device): a [VoiceSession] whose peers are [_ScriptedPeer]s
/// that walk connecting -> connected on their own, a loopback [Signaling] so
/// negotiation completes, and a [MockSpeakerLevelSource] the caller can drive to
/// simulate someone talking. Lets the screen run and widget-test without
/// libwebrtc. Swap [VoiceSession.host]'s factory for `WebRtcPeer.create`,
/// [newSignaling] for a socket channel, and the source for a WebRTC stats poller
/// to go live.
VoiceSession mockHostSession() => VoiceSession.host(_ScriptedPeer.new);

VoiceSession mockClientSession() => VoiceSession.client(_ScriptedPeer.new);

Signaling mockSignaling() => _NullSignaling();

MockSpeakerLevelSource mockSpeakerSource() => MockSpeakerLevelSource();

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
