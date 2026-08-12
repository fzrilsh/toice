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
const _nonceLength = 6; // App-layer group secret, not in the QR (see below).

/// Fixed group credentials plus the standard-format QR payload.
///
/// The [nonce] (ADR-002) is generated and persisted but deliberately NOT put in
/// the QR: the join QR stays a strictly standard `WIFI:` string so the iOS/
/// Android system Camera parses it (ADR-002 addendum). App-layer auth using the
/// nonce over the data channel is a later hardening phase; it rides in
/// [toJson]/[fromJson] so it survives persistence, not in [toWifiQrPayload].
class GroupCredentials {
  const GroupCredentials({
    required this.ssid,
    required this.password,
    required this.groupId,
    required this.nonce,
  });

  final String ssid;
  final String password;
  final String groupId;
  final String nonce;

  /// Generate fresh credentials from a cryptographic RNG.
  factory GroupCredentials.generate([Random? rng]) {
    final random = rng ?? Random.secure();
    final groupId = _randomString(random, _groupIdLength);
    return GroupCredentials(
      ssid: 'Toice-$groupId',
      password: _randomString(random, _passwordLength),
      groupId: groupId,
      nonce: _randomString(random, _nonceLength),
    );
  }

  /// Pigeon type crossing the native bridge (ADR-006).
  HotspotCredentials toHotspotCredentials() =>
      HotspotCredentials(ssid: ssid, password: password, groupId: groupId);

  /// Standard WiFi QR payload read natively by iOS 11+ / Android 9+ cameras
  /// (ADR-002 addendum). No escaping needed: [_alphabet] excludes the format's
  /// reserved characters. The nonce is intentionally absent (Option B): a
  /// non-standard tag risks a silent parse failure in the system Camera.
  String toWifiQrPayload() => 'WIFI:S:$ssid;T:WPA;P:$password;;';

  /// Parse a scanned standard `WIFI:` payload back into credentials. The nonce
  /// is not carried in the QR, so a scanned join has an empty nonce until the
  /// group's real nonce arrives over the data channel (later phase). [groupId]
  /// is derived from the `Toice-` SSID prefix. Throws [FormatException] on a
  /// malformed payload or a non-Toice SSID.
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
      nonce: '',
    );
  }

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'password': password,
    'groupId': groupId,
    'nonce': nonce,
  };

  factory GroupCredentials.fromJson(Map<String, dynamic> json) =>
      GroupCredentials(
        ssid: json['ssid'] as String,
        password: json['password'] as String,
        groupId: json['groupId'] as String,
        nonce: json['nonce'] as String,
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
