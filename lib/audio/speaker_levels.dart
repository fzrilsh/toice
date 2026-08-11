/// Speaker-level source boundary + active-speaker tracking (ADR-004).
///
/// The transport boundary for audio metering, keeping [DuckingEngine] fed
/// without any `flutter_webrtc` dependency in the logic layer. On device a
/// poller reads WebRTC per-track audio-level stats (Phase 6); in tests
/// [MockSpeakerLevelSource] scripts who is talking when. [ActiveSpeakerTracker]
/// folds each frame through the engine and exposes reactive active-speaker and
/// gain streams for the app state to bind.
library;

// `_engine` is a private field assigned from a public named ctor param (named
// params cannot be private), which trips this lint.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'ducking.dart';

/// Emits metering frames: one [SpeakerLevel] per active stream per frame.
///
/// Device impl polls WebRTC stats (Phase 6); the mock below drives it in tests.
abstract class SpeakerLevelSource {
  Stream<List<SpeakerLevel>> get levels;
}

/// Test/harness source: [push] a frame to emit it. Broadcast so multiple
/// listeners (tracker + UI) can subscribe.
class MockSpeakerLevelSource implements SpeakerLevelSource {
  final _controller = StreamController<List<SpeakerLevel>>.broadcast();

  @override
  Stream<List<SpeakerLevel>> get levels => _controller.stream;

  /// Emit one metering frame.
  void push(List<SpeakerLevel> frame) {
    if (!_controller.isClosed) _controller.add(frame);
  }

  Future<void> close() => _controller.close();
}

/// Subscribes a [SpeakerLevelSource], runs each frame through a [DuckingEngine],
/// and republishes the active speaker and per-peer gains.
///
/// This is the piece the app state listens to. [dispose] is idempotent and
/// cancels the subscription.
class ActiveSpeakerTracker {
  ActiveSpeakerTracker({
    required SpeakerLevelSource source,
    required DuckingEngine engine,
  }) : _engine = engine {
    _sub = source.levels.listen(_onFrame);
  }

  final DuckingEngine _engine;
  late final StreamSubscription<List<SpeakerLevel>> _sub;

  final _activeSpeaker = StreamController<String?>.broadcast();
  final _gains = StreamController<Map<String, double>>.broadcast();

  /// The stream currently at full gain, or null during silence. Emits on every
  /// frame that changes it.
  Stream<String?> get activeSpeaker => _activeSpeaker.stream;

  /// Per-peer gain decisions (peerId -> dB), emitted every frame.
  Stream<Map<String, double>> get gains => _gains.stream;

  String? _lastActive;
  bool _emittedActive = false;

  void _onFrame(List<SpeakerLevel> frame) {
    final levels = {for (final s in frame) s.peerId: s.dbfs};
    final gainMap = _engine.evaluate(levels);
    if (!_gains.isClosed) _gains.add(gainMap);

    final active = _engine.activeSpeaker;
    if (!_emittedActive || active != _lastActive) {
      _emittedActive = true;
      _lastActive = active;
      if (!_activeSpeaker.isClosed) _activeSpeaker.add(active);
    }
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await _activeSpeaker.close();
    await _gains.close();
  }
}
