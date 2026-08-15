import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toice/ui/pin_entry_screen.dart';

void main() {
  testWidgets('pops the entered PIN on a valid 4-6 digit entry', (
    tester,
  ) async {
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => PinEntryScreen(platformIsAndroid: false),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '4321');
    await tester.tap(find.text('Join call'));
    await tester.pumpAndSettle();

    expect(popped, '4321');
  });

  testWidgets('rejects a too-short PIN with an error, does not pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PinEntryScreen(platformIsAndroid: false)),
    );

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Join call'));
    await tester.pump();

    expect(find.textContaining('4 to 6 digit'), findsOneWidget);
  });

  testWidgets('iOS hides the scan-PIN option', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: PinEntryScreen(platformIsAndroid: false)),
    );
    expect(find.text('Scan PIN QR instead'), findsNothing);
  });
}
