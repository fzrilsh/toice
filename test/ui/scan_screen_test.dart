import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toice/group/group_credentials.dart';
import 'package:toice/ui/scan_screen.dart';

void main() {
  testWidgets('iOS branch: manual entry, no in-app camera', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ScanScreen(platformIsAndroid: false)),
    );

    // System-Camera guidance and manual SSID/password fields, no scanner view.
    expect(find.textContaining('built-in Camera'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('manual entry pops parsed credentials on valid input', (
    tester,
  ) async {
    GroupCredentials? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<GroupCredentials>(
                    MaterialPageRoute(
                      builder: (_) => ScanScreen(platformIsAndroid: false),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Toice-ABCD1234');
    await tester.enterText(find.byType(TextField).last, 'PASSWORD12345678');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.ssid, 'Toice-ABCD1234');
    expect(popped!.password, 'PASSWORD12345678');
    expect(popped!.groupId, 'ABCD1234');
  });

  testWidgets('manual entry shows an error on a non-Toice SSID', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ScanScreen(platformIsAndroid: false)),
    );

    await tester.enterText(find.byType(TextField).first, 'HomeWifi');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.text('Join'));
    await tester.pump();

    expect(find.textContaining('valid Toice SSID'), findsOneWidget);
  });
}
