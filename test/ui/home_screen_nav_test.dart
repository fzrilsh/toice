import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toice/ui/home_screen.dart';

void main() {
  testWidgets('client call-screen button navigates to CallScreen', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // The host call-screen button only appears after startHost, which crosses
    // the native bridge (device-only). The client route in the Join card is
    // always visible, so verify navigation through that.
    await tester.tap(find.text('Open call screen (client)'));
    await tester.pumpAndSettle();

    expect(find.text('Toice - Client'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
