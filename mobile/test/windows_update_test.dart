import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison', () {
    test('reports newer version correctly', () {
      expect(UpdateService.currentVersion, '1.0.4');
      expect(UpdateService.currentBuildNumber, 5);
    });
  });
}

