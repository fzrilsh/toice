import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:toice/group/group_credentials.dart';

void main() {
  group('GroupCredentials.generate', () {
    test('SSID is Toice-prefixed and within the 32-byte setSsid limit', () {
      final c = GroupCredentials.generate();
      expect(c.ssid, startsWith('Toice-'));
      expect(c.ssid, 'Toice-${c.groupId}');
      expect(c.ssid.codeUnits.length, lessThanOrEqualTo(32));
    });

    test('password length is a valid WPA2 passphrase (8-63)', () {
      final c = GroupCredentials.generate();
      expect(c.password.length, inInclusiveRange(8, 63));
    });

    test('groupId and password use only the unambiguous alphabet', () {
      // No I/L/O/U (misread), and none of the WIFI: reserved chars \ ; , : ".
      final allowed = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]+$');
      final c = GroupCredentials.generate();
      expect(allowed.hasMatch(c.groupId), isTrue, reason: c.groupId);
      expect(allowed.hasMatch(c.password), isTrue, reason: c.password);
    });

    test('two generations differ', () {
      final a = GroupCredentials.generate();
      final b = GroupCredentials.generate();
      expect(a.groupId, isNot(b.groupId));
      expect(a.password, isNot(b.password));
    });

    test('is deterministic given a seeded RNG (testability)', () {
      final a = GroupCredentials.generate(Random(42));
      final b = GroupCredentials.generate(Random(42));
      expect(a.ssid, b.ssid);
      expect(a.password, b.password);
    });
  });

  group('toWifiQrPayload', () {
    test('matches the standard WIFI: format', () {
      final c = GroupCredentials.generate();
      expect(
        c.toWifiQrPayload(),
        matches(RegExp(r'^WIFI:S:Toice-[0-9A-Z]+;T:WPA;P:[0-9A-Z]+;;$')),
      );
    });

    test('payload needs no escaping (guards the alphabet choice)', () {
      // If the alphabet ever gains a reserved char, this fails before a QR does
      // in the field. Check only the credential fields, not the format syntax.
      final c = GroupCredentials.generate();
      for (final field in [c.ssid, c.password]) {
        for (final ch in [r'\', ';', ',', ':', '"']) {
          expect(field.contains(ch), isFalse, reason: '$field contains $ch');
        }
      }
    });

    test(
      'tripPin is a 4-6 digit number, varies, and is NOT in the WiFi QR',
      () {
        final a = GroupCredentials.generate();
        final b = GroupCredentials.generate();
        expect(a.tripPin, matches(RegExp(r'^\d{4,6}$')));
        expect(a.tripPin, isNot(b.tripPin));
        // The join QR must stay a strictly standard WIFI: string.
        expect(a.toWifiQrPayload().contains(a.tripPin), isFalse);
      },
    );

    test(
      'pinQrPayload round-trips via pinFromQr, rejects junk and WiFi QR',
      () {
        final c = GroupCredentials.generate();
        expect(GroupCredentials.pinFromQr(c.pinQrPayload()), c.tripPin);
        expect(
          () => GroupCredentials.pinFromQr(c.toWifiQrPayload()),
          throwsFormatException,
        );
        expect(
          () => GroupCredentials.pinFromQr('TOICE-PIN:abcd'),
          throwsFormatException,
        );
      },
    );
  });

  group('fromWifiQrPayload', () {
    test('round-trips SSID/password/groupId from a scanned QR', () {
      final c = GroupCredentials.generate();
      final scanned = GroupCredentials.fromWifiQrPayload(c.toWifiQrPayload());
      expect(scanned.ssid, c.ssid);
      expect(scanned.password, c.password);
      expect(scanned.groupId, c.groupId);
      // PIN is not in the QR; a scanned join starts with an empty tripPin.
      expect(scanned.tripPin, isEmpty);
    });

    test('rejects a non-Toice SSID', () {
      expect(
        () =>
            GroupCredentials.fromWifiQrPayload('WIFI:S:Home;T:WPA;P:secret;;'),
        throwsFormatException,
      );
    });

    test('rejects a malformed payload', () {
      expect(
        () => GroupCredentials.fromWifiQrPayload('not a wifi qr'),
        throwsFormatException,
      );
    });
  });

  group('json round-trip', () {
    test('toJson/fromJson preserves every field including the tripPin', () {
      final c = GroupCredentials.generate();
      final back = GroupCredentials.fromJson(c.toJson());
      expect(back.ssid, c.ssid);
      expect(back.password, c.password);
      expect(back.groupId, c.groupId);
      expect(back.tripPin, c.tripPin);
    });
  });
}
