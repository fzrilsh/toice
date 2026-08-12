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

/// How the host AP was brought up (ADR-002 addendum).
///
/// [programmatic]: app configured the SoftAp with the fixed credentials
/// (Android 13+ reflection path). [manualRequired]: the app could not set
/// credentials, so the user must configure the hotspot by hand in Settings.
enum HostStartMode { programmatic, manualRequired }

/// Hotspot host/join control (ADR-001, ADR-002). Android: custom
/// SoftApConfiguration via reflection, else manual fallback. iOS cannot host,
/// and joins via the system Camera WiFi-QR flow, not this API.
@HostApi()
abstract class HotspotApi {
  @async
  HostStartMode startHost(HotspotCredentials credentials);

  @async
  void stopHost();

  /// Open the OS tethering/hotspot settings for the manual fallback path.
  @async
  void openTetherSettings();

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

/// Native -> Dart push channel for asynchronous hotspot state changes.
/// The host API is request/response only; the OS may tear the AP down or a
/// client link may drop out of band, so those arrive here.
@FlutterApi()
abstract class HotspotEvents {
  /// The hosted AP stopped (OS shutdown, failure, or explicit stopHost).
  void onHostStopped(String reason);

  /// This device's client connection to the hotspot came up or went down.
  void onClientStateChanged(bool connected);
}
