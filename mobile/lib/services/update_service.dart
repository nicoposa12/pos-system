import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../core/app_theme.dart';
import '../widgets/update_dialog.dart';

/// Centralized service for checking, tracking, and applying Shorebird OTA patches.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();

  bool _hasCheckedOnStartup = false;
  bool _isChecking = false;

  /// Whether the Shorebird update engine is available in the current environment
  /// (True on release APK/AAB builds, false in debug/testing).
  bool get isAvailable => _updater.isAvailable;

  /// Returns the current installed patch number, or null if on base release or unavailable.
  Future<int?> getCurrentPatchNumber() async {
    if (!isAvailable) return null;
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (_) {
      return null;
    }
  }

  /// Automatically checks for patches on app launch.
  /// If an update is detected, displays the progress dialog to patch the app cleanly.
  Future<void> checkForUpdatesOnStartup(BuildContext context) async {
    if (_hasCheckedOnStartup || !isAvailable) return;
    _hasCheckedOnStartup = true;

    try {
      // Safe 6-second timeout so offline or slow connections never block POS operations
      final status = await _updater
          .checkForUpdate(track: UpdateTrack.stable)
          .timeout(const Duration(seconds: 6));

      if (status == UpdateStatus.outdated) {
        if (!context.mounted) return;
        await UpdateProgressDialog.show(context, _updater);
      } else if (status == UpdateStatus.restartRequired) {
        if (!context.mounted) return;
        _showRestartRequiredBanner(context);
      }
    } catch (e) {
      debugPrint('[UpdateService] Startup update check error: $e');
    }
  }

  /// Manual check triggered by user tapping "Check for Updates" in Settings.
  Future<void> manualCheckForUpdates(BuildContext context) async {
    if (_isChecking) return;
    _isChecking = true;

    final messenger = ScaffoldMessenger.of(context);

    if (!isAvailable) {
      _isChecking = false;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Shorebird code push is only active on release builds.'),
          backgroundColor: AppTheme.accentPurple,
        ),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Checking for TindaKo updates...'),
          ],
        ),
        duration: Duration(seconds: 4),
      ),
    );

    try {
      final status = await _updater
          .checkForUpdate(track: UpdateTrack.stable)
          .timeout(const Duration(seconds: 8));

      messenger.hideCurrentSnackBar();

      if (status == UpdateStatus.outdated) {
        if (!context.mounted) return;
        await UpdateProgressDialog.show(context, _updater);
      } else if (status == UpdateStatus.restartRequired) {
        if (!context.mounted) return;
        _showRestartRequiredBanner(context);
      } else {
        final currentPatch = await getCurrentPatchNumber();
        final patchText = currentPatch != null ? ' (Patch #$currentPatch)' : '';
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('You are running the latest version$patchText.'),
              ],
            ),
            backgroundColor: AppTheme.accentTeal,
          ),
        );
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not check for updates. Check your internet connection.'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    } finally {
      _isChecking = false;
    }
  }

  void _showRestartRequiredBanner(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('An update was installed. Restart TindaKo to activate.'),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'RESTART',
          textColor: Colors.white,
          onPressed: () => SystemNavigator.pop(),
        ),
        backgroundColor: AppTheme.accentTeal,
        duration: const Duration(seconds: 10),
      ),
    );
  }
}

