import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toice/group/credential_store.dart';
import 'package:toice/group/group_controller.dart';
import 'package:toice/ui/home_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('landing shows the empty-state welcome and both actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(controller: GroupController())),
    );

    expect(find.text('Ride connected'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
    expect(find.text('Join group'), findsOneWidget);
  });

  testWidgets('Create group hosts and shows the QR host screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(controller: GroupController())),
    );

    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    // CreateScreen renders with the generated fixed credentials.
    expect(find.text('Host group'), findsOneWidget);
    expect(find.textContaining('SSID: Toice-'), findsOneWidget);
    expect(find.text('Start call'), findsOneWidget);
  });

  testWidgets('a persisted trip auto-restores as an active-trip banner', (
    tester,
  ) async {
    // Seed a trip, then a fresh controller restores it on launch.
    final store = CredentialStore();
    final seeder = GroupController(store: store);
    await seeder.create();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(controller: GroupController(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Active trip: Toice-'), findsOneWidget);
    expect(find.text('End trip'), findsOneWidget);
  });
}
