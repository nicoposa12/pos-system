import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison', () {
    test('exposes valid default version and positive build number', () {
      expect(
        UpdateService.currentVersion,
        matches(RegExp(r'^\d+\.\d+\.\d+$')),
      );
      expect(UpdateService.currentBuildNumber, greaterThan(0));
    });

    test('detects newer semantic versions across patch, minor, and major bumps', () {
      expect(UpdateService.isNewerVersion('1.0.5', '1.0.4'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.10', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('v1.0.6', '1.0.4'), isTrue);
    });

    test('compares build numbers when semantic versions are equal', () {
      expect(
        UpdateService.isNewerVersion(
          '1.0.6',
          '1.0.6',
          remoteBuildNumber: 7,
          currentBuildNumber: 6,
        ),
        isTrue,
      );
      expect(
        UpdateService.isNewerVersion(
          '1.0.6',
          '1.0.6',
          remoteBuildNumber: 6,
          currentBuildNumber: 6,
        ),
        isFalse,
      );
      expect(
        UpdateService.isNewerVersion(
          '1.0.6',
          '1.0.6',
          remoteBuildNumber: 5,
          currentBuildNumber: 6,
        ),
        isFalse,
      );
    });

    test('rejects older, equal without build bump, or empty versions', () {
      expect(UpdateService.isNewerVersion('1.0.4', '1.0.4'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.3', '1.0.4'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('', '1.0.4'), isFalse);
    });
  });
}
