import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toice/audio/rtc_peer.dart';
import 'package:toice/ui/call_screen.dart';

void main() {
  testWidgets('host screen: add rider shows a tile that reaches connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          session: mockHostSession(),
          newSignaling: mockSignaling,
        ),
      ),
    );

    expect(find.text('No peers yet'), findsOneWidget);

    await tester.tap(find.text('Add rider'));
    await tester.pump(); // link added, connecting
    expect(find.text('rider-1'), findsOneWidget);
    expect(find.text(VoiceConnectionState.connecting.name), findsOneWidget);

    // Scripted peer flips to connected after ~300ms.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(VoiceConnectionState.connected.name), findsOneWidget);
  });

  testWidgets('client screen: connect then show the host link', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          session: mockClientSession(),
          newSignaling: mockSignaling,
        ),
      ),
    );

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('host'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(VoiceConnectionState.connected.name), findsOneWidget);
    // Connect FAB is gone once linked (client links to one host).
    expect(find.text('Connect'), findsNothing);
  });
}
