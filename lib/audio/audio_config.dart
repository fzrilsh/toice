/// Audio pipeline configuration (ADR-004).
///
/// A pure decision object the Phase 6 WebRTC pipeline consumes: DTX is always on
/// (silence handling), and echo cancellation is reduced when a headset is in use
/// (no acoustic loop, so AEC wastes CPU). No audio here, no `flutter_webrtc`.
library;

/// Where audio is played/captured. Determines whether an acoustic echo loop
/// exists (device speaker) or not (headset).
enum AudioRoute { deviceSpeaker, wiredHeadset, btHeadset }

/// Resolved WebRTC audio-pipeline settings for the current route.
class AudioPipelineConfig {
  const AudioPipelineConfig({
    required this.route,
    required this.aecEnabled,
    this.dtxEnabled = true,
  });

  final AudioRoute route;

  /// Acoustic echo cancellation. On for the device speaker (mic hears the
  /// speaker); off for headsets (no loop), saving pipeline CPU per ADR-004.
  final bool aecEnabled;

  /// Opus discontinuous transmission. Always on (ADR-004 silence handling).
  final bool dtxEnabled;

  /// Config for [route], encoding the ADR-004 rules.
  factory AudioPipelineConfig.forRoute(AudioRoute route) => AudioPipelineConfig(
    route: route,
    aecEnabled: route == AudioRoute.deviceSpeaker,
  );
}
