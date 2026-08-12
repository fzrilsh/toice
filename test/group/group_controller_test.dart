import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toice/audio/voice_session.dart';
import 'package:toice/group/credential_store.dart';
import 'package:toice/group/group_controller.dart';
import 'package:toice/group/group_credentials.dart';

void main() {
  late GroupController controller;
  late CredentialStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = CredentialStore();
    controller = GroupController(store: store);
  });

  test('create generates credentials, persists them, hosts', () async {
    var notified = 0;
    controller.addListener(() => notified++);

    final creds = await controller.create();

    expect(controller.credentials, creds);
    expect(controller.role, SessionRole.host);
    expect(controller.hasActiveTrip, isTrue);
    expect((await store.load())!.ssid, creds.ssid);
    expect(notified, 1);
  });

  test('joinWith persists the given credentials as a client', () async {
    final creds = GroupCredentials.generate();
    await controller.joinWith(creds);

    expect(controller.credentials!.ssid, creds.ssid);
    expect(controller.role, SessionRole.client);
    expect((await store.load())!.ssid, creds.ssid);
  });

  test('restore loads a persisted trip', () async {
    final creds = GroupCredentials.generate();
    await store.save(creds);

    final restored = await controller.restore();
    expect(restored, isTrue);
    expect(controller.credentials!.ssid, creds.ssid);
    expect(controller.role, SessionRole.client);
  });

  test('restore returns false when there is no persisted trip', () async {
    expect(await controller.restore(), isFalse);
    expect(controller.hasActiveTrip, isFalse);
  });

  test('endTrip clears persisted credentials and state', () async {
    await controller.create();
    await controller.endTrip();

    expect(controller.credentials, isNull);
    expect(controller.role, isNull);
    expect(controller.hasActiveTrip, isFalse);
    expect(await store.load(), isNull);
  });
}
