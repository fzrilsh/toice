/// Reactive app state store (ADR-003/004).
///
/// One source of truth for the call/roster UI, binding the three live inputs
/// the screen cares about: per-peer connection state (from [VoiceSession]),
/// the active speaker (from [ActiveSpeakerTracker]), and the current host +
/// handoff phase (mirrored from the election daemon). A [ChangeNotifier] so the
/// UI rebuilds on change with no new dependency.
///
/// The store does not own the election: it reflects host status pushed in via
/// [updateHostStatus], keeping the daemon the single owner of that logic.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:toice/audio/speaker_levels.dart';
import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/audio/voice_session.dart';
import 'package:toice/election/handoff.dart';

/// One rider as the UI renders them: connection, speaking, and host role.
@immutable
class RiderView {
  const RiderView({
    required this.peerId,
    required this.connection,
    required this.isSpeaking,
    required this.isHost,
  });

  final String peerId;
  final VoiceConnectionState connection;
  final bool isSpeaking;
  final bool isHost;

  @override
  bool operator ==(Object other) =>
      other is RiderView &&
      other.peerId == peerId &&
      other.connection == connection &&
      other.isSpeaking == isSpeaking &&
      other.isHost == isHost;

  @override
  int get hashCode => Object.hash(peerId, connection, isSpeaking, isHost);
}

/// Binds session + speaker + host state into a reactive [riders] view.
class SessionStore extends ChangeNotifier {
  SessionStore({
    required VoiceSession session,
    required ActiveSpeakerTracker speaker,
  }) : _session = session {
    _connections = session.connections;
    _connSub = session.connectionChanges.listen((c) {
      _connections = c;
      notifyListeners();
    });
    _activeSub = speaker.activeSpeaker.listen((id) {
      _activeSpeaker = id;
      notifyListeners();
    });
  }

  final VoiceSession _session;
  late final StreamSubscription<Map<String, VoiceConnectionState>> _connSub;
  late final StreamSubscription<String?> _activeSub;

  Map<String, VoiceConnectionState> _connections = {};
  String? _activeSpeaker;
  String? _currentHost;
  HandoffState _handoffState = HandoffState.stable;

  SessionRole get role => _session.role;
  String? get activeSpeaker => _activeSpeaker;
  String? get currentHost => _currentHost;
  HandoffState get handoffState => _handoffState;

  /// Mirror the election daemon's host status. Called by the daemon's owner
  /// after each election step; the store only reflects it for display.
  void updateHostStatus({
    required String? currentHost,
    required HandoffState handoffState,
  }) {
    if (currentHost == _currentHost && handoffState == _handoffState) return;
    _currentHost = currentHost;
    _handoffState = handoffState;
    notifyListeners();
  }

  /// The roster the UI renders, one entry per connected/known peer.
  List<RiderView> get riders => [
    for (final e in _connections.entries)
      RiderView(
        peerId: e.key,
        connection: e.value,
        isSpeaking: e.key == _activeSpeaker,
        isHost: e.key == _currentHost,
      ),
  ];

  @override
  void dispose() {
    _connSub.cancel();
    _activeSub.cancel();
    super.dispose();
  }
}
