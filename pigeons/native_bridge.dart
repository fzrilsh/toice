// Platform channel definitions for the native bridge (ADR-006).
//
// This is the source of truth for every Dart <-> native call signature.
// Regenerate bindings after editing:
//
//   fvm dart run pigeon --input pigeons/native_bridge.dart
//
// Outputs (do not edit generated files by hand):
//   - lib/native_bridge/native_bridge.g.dart
//   - android/app/src/main/kotlin/com/fzrilsh/toice/NativeBridge.g.kt
//   - ios/Runner/NativeBridge.g.swift

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/native_bridge/native_bridge.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/fzrilsh/toice/NativeBridge.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.fzrilsh.toice'),
    swiftOut: 'ios/Runner/NativeBridge.g.swift',
    dartPackageName: 'toice',
  ),
)
/// Fixed WiFi hotspot credentials shared for the life of a trip (ADR-002).
/// Reused by every subsequent host so iOS auto-rejoins without a new prompt.
class HotspotCredentials {
  HotspotCredentials({
    required this.ssid,
    required this.password,
    required this.groupId,
  });

  String ssid;
  String password;
  String groupId;
}

/// OS thermal state, normalized across platforms (ADR-003 thermal_score).
/// Maps ProcessInfo.thermalState (iOS) and PowerManager thermal status
/// (Android) onto a common ordinal.
enum ThermalState { nominal, fair, serious, critical }

/// Hotspot host/join control (ADR-001, ADR-002). Android: custom
/// SoftApConfiguration. iOS: NEHotspotConfiguration join (host not supported).
@HostApi()
abstract class HotspotApi {
  @async
  void startHost(HotspotCredentials credentials);

  @async
  void stopHost();

  @async
  void joinAsClient(HotspotCredentials credentials);

  @async
  void leave();
}

/// Sensor reads feeding the ADR-003 fitness score.
@HostApi()
abstract class SensorApi {
  /// Battery level 0-100.
  @async
  int getBatteryLevel();

  @async
  ThermalState getThermalState();

  /// RSSI (dBm) to each connected peer, keyed by peer/group member id.
  /// Used to derive the worst-case (minimum) RSSI for rssi_score.
  @async
  Map<String, int> getRssiToPeers();
}

/// Keep-alive session control (ADR-005). Android: foreground service with
/// persistent notification. iOS: background audio session.
@HostApi()
abstract class BackgroundApi {
  @async
  void startForegroundSession();

  @async
  void stopForegroundSession();
}
