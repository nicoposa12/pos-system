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

  testWidgets('UpdateProgressDialog displays progress bar and percentage during download',
      (WidgetTester tester) async {
    final fakeUpdater = _FakeUpdater(shouldSucceed: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateProgressDialog(updater: fakeUpdater),
        ),
      ),
    );

    // Initial render should show updating text and progress bar
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

  testWidgets('UpdateProgressDialog displays friendly error on failure',
      (WidgetTester tester) async {
    final fakeUpdater = _FakeUpdater(shouldSucceed: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateProgressDialog(updater: fakeUpdater),
        ),
      ),
    );

    // Wait for the simulated failure to occur
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Update Interrupted'), findsOneWidget);
    expect(find.text('Continue to App'), findsOneWidget);
  });
}
