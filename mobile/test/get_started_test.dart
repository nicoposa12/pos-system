import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/core/app_theme.dart';
import 'package:tindako/screens/get_started_screen.dart';

void main() {
  testWidgets('GetStartedScreen renders CTA button visible without scrolling on standard phone',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const GetStartedScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify brand header, carousel, and dots are visible
    expect(find.text('TindaKo'), findsOneWidget);
    expect(find.text('Cloud-Connected'), findsOneWidget);

    // Verify the primary CTA button and footer are immediately on-screen
    final ctaFinder = find.text('Sign In to Register');
    expect(ctaFinder, findsOneWidget);
    expect(tester.getTopLeft(ctaFinder).dy, lessThan(740));
    expect(tester.getBottomRight(ctaFinder).dy, lessThan(740));

    final noteFinder = find.text('Accounts are provisioned by Administrator');
    expect(noteFinder, findsOneWidget);
    expect(tester.getBottomRight(noteFinder).dy, lessThan(740));
  });

  testWidgets('GetStartedScreen renders CTA button visible on compact budget phone (320x568)',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const GetStartedScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final ctaFinder = find.text('Sign In to Register');
    expect(ctaFinder, findsOneWidget);
    expect(tester.getBottomRight(ctaFinder).dy, lessThanOrEqualTo(568));
  });
}

