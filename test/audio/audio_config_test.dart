import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/audio_config.dart';

void main() {
  test('DTX is always on regardless of route', () {
    for (final route in AudioRoute.values) {
      expect(AudioPipelineConfig.forRoute(route).dtxEnabled, isTrue);
    }
  });

  test('AEC is on for the device speaker (acoustic loop exists)', () {
    expect(
      AudioPipelineConfig.forRoute(AudioRoute.deviceSpeaker).aecEnabled,
      isTrue,
    );
  });

  test('AEC is off for headset routes (no loop, saves CPU)', () {
    expect(
      AudioPipelineConfig.forRoute(AudioRoute.wiredHeadset).aecEnabled,
      isFalse,
    );
    expect(
      AudioPipelineConfig.forRoute(AudioRoute.btHeadset).aecEnabled,
      isFalse,
    );
  });
}
