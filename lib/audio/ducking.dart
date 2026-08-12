/// Loudest-speaker-wins ducking (ADR-004).
///
/// Pure decision logic: given a snapshot of each stream's audio level, decide
/// which one is "active" (full gain) and attenuate the rest, with hold-time
/// hysteresis so two similarly loud speakers don't cause rapid switching. This
/// file must stay free of `flutter_webrtc`: it works on plain numbers so it runs
/// under `flutter test` with no device. The Phase 6 pipeline feeds it real
/// per-track metering and applies the returned gains to live tracks.
library;

// `_config`/`_clock` are private fields assigned from public named ctor params
// (named params cannot be private), which trips this lint.
// ignore_for_file: prefer_initializing_formals

/// One audio-level metering sample for one stream.
///
/// [dbfs] follows the WebRTC convention: 0 is loudest, negative is quieter
/// (roughly -127..0). Higher (closer to 0) means louder.
class SpeakerLevel {
  const SpeakerLevel(this.peerId, this.dbfs);

  final String peerId;
  final double dbfs;
}

/// Tunables for [DuckingEngine], defaults per ADR-004.
class DuckingConfig {
  const DuckingConfig({
    this.activeGainDb = 0,
    this.duckedGainDb = -18,
    this.holdTime = const Duration(milliseconds: 400),
    this.activationFloorDbfs = -50,
  });

  /// Gain applied to the active (loudest) speaker.
  final double activeGainDb;

  /// Gain applied to every other stream (ADR-004: ~15-20 dB attenuation, not
  /// muted).
  final double duckedGainDb;

  /// A challenger must stay strictly loudest for this long before it steals
  /// "active" from the incumbent (anti-thrash between similar speakers).
  final Duration holdTime;

  /// Levels below this are treated as not-speaking; ambient noise never grabs
  /// "active". When nobody clears it, nobody is ducked.
  final double activationFloorDbfs;
}

/// Decides per-stream gain from level snapshots, with hold-time hysteresis.
///
/// Feed it one [evaluate] per metering frame. The active speaker only changes
/// once a louder challenger has held the lead for [DuckingConfig.holdTime];
/// clock is injected so the hold is testable without real time.
class DuckingEngine {
  DuckingEngine({
    DuckingConfig config = const DuckingConfig(),
    required DateTime Function() clock,
  }) : _config = config,
       _clock = clock;

  final DuckingConfig _config;
  final DateTime Function() _clock;

  /// Stream currently at full gain, or null when everyone is below the floor.
  String? _active;

  /// Challenger accumulating time toward stealing active, and since when.
  String? _pending;
  DateTime? _pendingSince;

  String? get activeSpeaker => _active;

  /// Map the current [levelsByPeer] (peerId -> dBFS) to a gain decision
  /// (peerId -> dB). The active speaker gets [DuckingConfig.activeGainDb], the
  /// rest [DuckingConfig.duckedGainDb]. If nobody clears the activation floor,
  /// everyone sits at active gain (silence: no ducking).
  Map<String, double> evaluate(Map<String, double> levelsByPeer) {
    final loudest = _loudestAboveFloor(levelsByPeer);

    if (loudest == null) {
      // Silence: drop the incumbent and duck nobody.
      _active = null;
      _pending = null;
      _pendingSince = null;
      return {for (final id in levelsByPeer.keys) id: _config.activeGainDb};
    }

    if (_active == null) {
      // No incumbent: the loudest takes over immediately.
      _active = loudest;
      _pending = null;
      _pendingSince = null;
    } else if (loudest == _active) {
      // Incumbent still loudest: cancel any pending challenge.
      _pending = null;
      _pendingSince = null;
    } else {
      // A challenger is loudest. Start or continue its hold window.
      final now = _clock();
      if (_pending != loudest) {
        _pending = loudest;
        _pendingSince = now;
      } else if (now.difference(_pendingSince!) >= _config.holdTime) {
        _active = loudest;
        _pending = null;
        _pendingSince = null;
      }
    }

    return {
      for (final id in levelsByPeer.keys)
        id: id == _active ? _config.activeGainDb : _config.duckedGainDb,
    };
  }

  /// Loudest peer strictly above the activation floor, or null if none.
  String? _loudestAboveFloor(Map<String, double> levels) {
    String? best;
    double? bestDbfs;
    levels.forEach((id, dbfs) {
      if (dbfs < _config.activationFloorDbfs) return;
      if (bestDbfs == null || dbfs > bestDbfs!) {
        best = id;
        bestDbfs = dbfs;
      }
    });
    return best;
  }
}
