import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toice/group/credential_store.dart';
import 'package:toice/group/group_credentials.dart';

void main() {
  late CredentialStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = CredentialStore();
  });

  test('load returns null when nothing is saved', () async {
    expect(await store.load(), isNull);
  });

  test(
    'save then load round-trips every field including the tripPin',
    () async {
      final creds = GroupCredentials.generate();
      await store.save(creds);

      final back = await store.load();
      expect(back, isNotNull);
      expect(back!.ssid, creds.ssid);
      expect(back.password, creds.password);
      expect(back.groupId, creds.groupId);
      expect(back.tripPin, creds.tripPin);
    },
  );

  test('save replaces the previous credentials', () async {
    final first = GroupCredentials.generate();
    final second = GroupCredentials.generate();
    await store.save(first);
    await store.save(second);
    expect((await store.load())!.ssid, second.ssid);
  });

  test('clear removes the persisted credentials', () async {
    await store.save(GroupCredentials.generate());
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('a corrupt blob loads as null instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'toice.group_credentials': jsonEncode({'ssid': 'only-ssid'}),
    });
    expect(await store.load(), isNull);
  });
}
