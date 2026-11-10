import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:tindako/services/update_service.dart';
import 'package:tindako/widgets/update_dialog.dart';

class _FakeUpdater extends Fake implements ShorebirdUpdater {
  final bool shouldSucceed;
  _FakeUpdater({this.shouldSucceed = true});

  @override
  bool get isAvailable => true;

  @override
  Future<void> update({UpdateTrack? track}) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (!shouldSucceed) {
      throw Exception('Network timeout');
    }
  }
}

void main() {
  test('UpdateService reports isAvailable as false in test runner', () {
    expect(UpdateService.instance.isAvailable, isFalse);
  });

  testWidgets('UpdateProgressDialog displays decision state with Later and Update Now',
      (WidgetTester tester) async {
    final fakeUpdater = _FakeUpdater(shouldSucceed: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateProgressDialog(updater: fakeUpdater),
        ),
      ),
    );

    // Initial render should show decision state with Later and Update Now
    expect(find.text('New Update Available'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Update Now'), findsOneWidget);

    // Tap Update Now to trigger download
    await tester.tap(find.text('Update Now'));
    await tester.pump();

    // Now it transitions to downloading state
    expect(find.text('Updating TindaKo POS'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('%'), findsOneWidget);

    // Advance time to allow update to complete
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Completed state should show ready title and restart action
    expect(find.text('Update Ready!'), findsOneWidget);
    expect(find.text('Restart App Now'), findsOneWidget);
    expect(find.text('Restart Later'), findsOneWidget);
  });

  testWidgets('UpdateProgressDialog dismisses when tapping Later',
      (WidgetTester tester) async {
    final fakeUpdater = _FakeUpdater(shouldSucceed: true);
    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await UpdateProgressDialog.show(context, fakeUpdater);
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('New Update Available'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);

    // Tap Later
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // Dialog is dismissed and returned false
    expect(find.text('New Update Available'), findsNothing);
    expect(dialogResult, isFalse);
  });

  testWidgets('UpdateProgressDialog displays friendly error on failure after Update Now',
      (WidgetTester tester) async {
    final fakeUpdater = _FakeUpdater(shouldSucceed: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateProgressDialog(updater: fakeUpdater),
        ),
      ),
    );

    // Initial decision state
    expect(find.text('Update Now'), findsOneWidget);
    await tester.tap(find.text('Update Now'));
    await tester.pump();

    // Wait for the simulated failure to occur
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Update Interrupted'), findsOneWidget);
    expect(find.text('Continue to App'), findsOneWidget);
    expect(find.text('Retry Update'), findsOneWidget);
  });
}
