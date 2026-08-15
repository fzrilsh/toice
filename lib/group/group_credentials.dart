/// Group WiFi credential generation and QR payload encoding (ADR-002).
///
/// Fixed for the life of a trip: generated once at group creation, reused by
/// every subsequent host so devices auto-rejoin without re-pairing. This is the
/// generation primitive only; persistence and QR rendering live elsewhere.
library;

import 'dart:math';

import 'package:toice/native_bridge/native_bridge.g.dart';

/// Crockford base32 alphabet minus I/L/O/U: unambiguous when read aloud or
/// typed by hand for the Android manual-hotspot fallback (Task 4). Also free of
/// the `\ ; , : "` characters that the WIFI: QR format requires escaping, so
/// [GroupCredentials.toWifiQrPayload] needs no escaping.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

const _groupIdLength = 8; // SSID "Toice-XXXXXXXX" = 14 bytes, well under 32.
const _passwordLength = 16; // Valid WPA2 range is 8-63 chars.
const _tripPinLength = 6; // Numeric PIN the client types (or scans) to auth.

/// Prefix on the optional PIN-only QR so a stray scan can't be mistaken for it.
const _pinQrPrefix = 'TOICE-PIN:';

/// Fixed group credentials plus the standard-format QR payload.
///
/// The [tripPin] (ADR-002 nonce, refined to a short numeric PIN in Phase 4.5) is
/// generated and persisted but deliberately NOT put in the WiFi QR: the join QR
/// stays a strictly standard `WIFI:` string so the iOS/Android system Camera
/// parses it (ADR-002 addendum). The host shows the PIN in large text and, on
/// Android, as an optional [pinQrPayload] second QR; the client types or scans
/// it. It is the shared secret for the app-layer HMAC handshake (Phase 4.5 auth)
/// and rides in [toJson]/[fromJson], not in [toWifiQrPayload].
class GroupCredentials {
  const GroupCredentials({
    required this.ssid,
    required this.password,
    required this.groupId,
    required this.tripPin,
  });

  final String ssid;
  final String password;
  final String groupId;
  final String tripPin;

  /// Generate fresh credentials from a cryptographic RNG.
  factory GroupCredentials.generate([Random? rng]) {
    final random = rng ?? Random.secure();
    final groupId = _randomString(random, _groupIdLength);
    return GroupCredentials(
      ssid: 'Toice-$groupId',
      password: _randomString(random, _passwordLength),
      groupId: groupId,
      tripPin: _randomDigits(random, _tripPinLength),
    );
  }

  /// Pigeon type crossing the native bridge (ADR-006).
  HotspotCredentials toHotspotCredentials() =>
      HotspotCredentials(ssid: ssid, password: password, groupId: groupId);

  /// Standard WiFi QR payload read natively by iOS 11+ / Android 9+ cameras
  /// (ADR-002 addendum). No escaping needed: [_alphabet] excludes the format's
  /// reserved characters. The trip PIN is intentionally absent (Option B): a
  /// non-standard tag risks a silent parse failure in the system Camera.
  String toWifiQrPayload() => 'WIFI:S:$ssid;T:WPA;P:$password;;';

  /// Optional PIN-only QR (Android in-app scan auto-fill). Not a WIFI: string,
  /// so it never reaches the system Camera join path; the app scans it after
  /// the network is already joined. iOS clients type the PIN by hand.
  String pinQrPayload() => '$_pinQrPrefix$tripPin';

  /// Read the trip PIN out of a [pinQrPayload] scan. Throws [FormatException] on
  /// anything that isn't a well-formed Toice PIN QR.
  static String pinFromQr(String payload) {
    if (!payload.startsWith(_pinQrPrefix)) {
      throw FormatException('not a Toice PIN QR', payload);
    }
    final pin = payload.substring(_pinQrPrefix.length);
    if (pin.isEmpty || !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw FormatException('not a 4-6 digit PIN', pin);
    }
    return pin;
  }

  /// Parse a scanned standard `WIFI:` payload back into credentials. The PIN is
  /// not carried in the WiFi QR, so a scanned join has an empty [tripPin] until
  /// the rider enters it on the PIN screen. [groupId] is derived from the
  /// `Toice-` SSID prefix. Throws [FormatException] on a malformed payload or a
  /// non-Toice SSID.
  factory GroupCredentials.fromWifiQrPayload(String payload) {
    final ssid = _wifiField(payload, 'S');
    final password = _wifiField(payload, 'P');
    if (ssid == null || password == null) {
      throw FormatException('not a WIFI: payload', payload);
    }
    if (!ssid.startsWith('Toice-')) {
      throw FormatException('not a Toice SSID', ssid);
    }
    return GroupCredentials(
      ssid: ssid,
      password: password,
      groupId: ssid.substring('Toice-'.length),
      tripPin: '',
    );
  }

  /// Copy with a filled-in [tripPin] (set once the rider enters it).
  GroupCredentials withTripPin(String pin) => GroupCredentials(
    ssid: ssid,
    password: password,
    groupId: groupId,
    tripPin: pin,
  );

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'password': password,
    'groupId': groupId,
    'tripPin': tripPin,
  };

  factory GroupCredentials.fromJson(Map<String, dynamic> json) =>
      GroupCredentials(
        ssid: json['ssid'] as String,
        password: json['password'] as String,
        groupId: json['groupId'] as String,
        tripPin: json['tripPin'] as String,
      );
}

/// Read one `KEY:value` field from a `WIFI:` payload; null if absent.
String? _wifiField(String payload, String key) {
  final match = RegExp('(?:WIFI:|;)$key:([^;]*);').firstMatch(payload);
  return match?.group(1);
}

String _randomString(Random random, int length) => String.fromCharCodes(
  Iterable.generate(
    length,
    (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
  ),
);

String _randomDigits(Random random, int length) => String.fromCharCodes(
  Iterable.generate(length, (_) => 0x30 + random.nextInt(10)),
);
