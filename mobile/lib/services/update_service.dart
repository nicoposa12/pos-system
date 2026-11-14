import 'dart:async';
import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../core/app_theme.dart';
import '../widgets/update_dialog.dart';
import '../widgets/windows_update_dialog.dart';
import 'api_service.dart';

/// Centralized service for checking, tracking, and applying updates.
/// Supports Shorebird OTA patches on Android/iOS and in-app auto-updates on Windows desktop.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.6',
  );
  static const int currentBuildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 6,
  );

  final ShorebirdUpdater _updater = ShorebirdUpdater();

  bool _hasCheckedOnStartup = false;
  bool _isChecking = false;

  /// Whether running on a desktop platform (Windows, macOS, Linux).
  bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether the Shorebird update engine is available in the current environment
  /// (True on release APK/AAB builds, false on desktop or in debug/testing).
  bool get isAvailable => !isDesktop && _updater.isAvailable;

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

  /// Automatically checks for updates on app launch.
  /// On mobile, downloads Shorebird OTA patches. On Windows, silently checks for desktop updates.
  Future<void> checkForUpdatesOnStartup(BuildContext context) async {
    if (_hasCheckedOnStartup) return;
    _hasCheckedOnStartup = true;

    if (isDesktop) {
      await _checkDesktopUpdateSilently(context);
      return;
    }

    if (!isAvailable) return;

    try {
      final status = await _updater
          .checkForUpdate(track: UpdateTrack.stable)
          .timeout(const Duration(seconds: 6));

      if (status == UpdateStatus.outdated) {
        if (!context.mounted) return;
        _showMobileUpdateAvailableBanner(context);
      } else if (status == UpdateStatus.restartRequired) {
        if (!context.mounted) return;
        _showRestartRequiredBanner(context);
      }
    } catch (e) {
      debugPrint('[UpdateService] Mobile startup update check error: $e');
    }
  }

  bool _hasDesktopUpdate(_DesktopUpdateInfo update) {
    return isNewerVersion(
      update.version,
      currentVersion,
      remoteBuildNumber: update.buildNumber,
      currentBuildNumber: currentBuildNumber,
    );
  }

  Future<void> _openWindowsUpdateDialog(
    BuildContext context,
    _DesktopUpdateInfo update,
  ) {
    return WindowsUpdateDialog.show(
      context,
      version: update.version,
      downloadUrl: update.downloadUrl,
      releaseNotes: update.releaseNotes,
      forceUpdate: update.forceUpdate,
    );
  }

  void _showCheckErrorBanner(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.accentRose,
      ),
    );
  }

  /// Silent desktop check on startup: if an update is found, displays an action banner.
  Future<void> _checkDesktopUpdateSilently(BuildContext context) async {
    try {
      final update = await _fetchDesktopUpdateManifest(
        timeout: const Duration(seconds: 15),
      );
      if (update != null && _hasDesktopUpdate(update)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('TindaKo v${update.version} is available with new updates.'),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'UPDATE NOW',
              textColor: AppTheme.accentOrange,
              onPressed: () {
                _openWindowsUpdateDialog(context, update);
              },
            ),
            backgroundColor: AppTheme.cardDark,
            duration: const Duration(seconds: 12),
          ),
        );
      }
    } catch (_) {}
  }

  /// Manual check triggered by user tapping "Check for Updates" in Settings.
  Future<void> manualCheckForUpdates(BuildContext context) async {
    if (_isChecking) return;
    _isChecking = true;

    final messenger = ScaffoldMessenger.of(context);

    // Desktop handling: query cloud backend for latest Windows installer
    if (isDesktop) {
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
              Text('Checking for TindaKo Windows updates...'),
            ],
          ),
          duration: Duration(seconds: 25),
        ),
      );

      try {
        final update = await _fetchDesktopUpdateManifest(
          timeout: const Duration(seconds: 25),
          rethrowOnError: true,
        );
        messenger.hideCurrentSnackBar();

        if (update != null && _hasDesktopUpdate(update)) {
          if (!context.mounted) return;
          await _openWindowsUpdateDialog(context, update);
        } else {
          if (!context.mounted) return;
          await _showDesktopUpdateStatus(context);
        }
      } catch (e) {
        messenger.hideCurrentSnackBar();
        _showCheckErrorBanner(
          messenger,
          'Could not check for updates. Server may be waking up or offline.',
        );
      } finally {
        _isChecking = false;
      }
      return;
    }

    // Mobile / Shorebird handling
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
      _showCheckErrorBanner(
        messenger,
        'Could not check for updates. Check your internet connection.',
      );
    } finally {
      _isChecking = false;
    }
  }

  /// Fetches the update manifest from the cloud backend.
  Future<_DesktopUpdateInfo?> _fetchDesktopUpdateManifest({
    Duration timeout = const Duration(seconds: 20),
    bool rethrowOnError = false,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
      ),
    );

    final url = '${ApiService.instance.baseUrl}/app/version';

    try {
      final res = await dio.get(url);
      if (res.statusCode == 200 && res.data is Map) {
        final win = res.data['windows'];
        if (win is Map) {
          final ver = win['version']?.toString().trim() ?? '';
          final dlUrl = win['download_url']?.toString().trim() ?? '';
          final notes = win['release_notes']?.toString() ?? '';
          final force = win['force_update'] == true;
          final build = int.tryParse(win['build_number']?.toString() ?? '');
          if (ver.isNotEmpty && dlUrl.isNotEmpty) {
            return _DesktopUpdateInfo(
              version: ver,
              buildNumber: build,
              downloadUrl: dlUrl,
              releaseNotes: notes,
              forceUpdate: force,
            );
          }
        }
      }
      if (rethrowOnError) {
        throw const FormatException('Invalid update manifest received.');
      }
    } catch (e) {
      debugPrint('[UpdateService] Failed to fetch cloud version: $e');
      if (rethrowOnError) rethrow;
    }

    return null;
  }

  /// Compares whether [remote] (and optional [remoteBuildNumber]) is strictly
  /// newer than [current] (and optional [currentBuildNumber]).
  @visibleForTesting
  static bool isNewerVersion(
    String remote,
    String current, {
    int? remoteBuildNumber,
    int? currentBuildNumber,
  }) {
    final cleanRemote = remote.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleanRemote.isEmpty) return false;
    final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');
    final rParts = cleanRemote.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final cParts = cleanCurrent.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = rParts.length > cParts.length ? rParts.length : cParts.length;
    for (int i = 0; i < len; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    if (remoteBuildNumber != null && currentBuildNumber != null) {
      return remoteBuildNumber > currentBuildNumber;
    }
    return false;
  }

  /// Displays a clean desktop update dialog when up to date.
  Future<void> _showDesktopUpdateStatus(BuildContext context) async {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentTeal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.accentTeal,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'TindaKo is Up to Date',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.borderColor(dialogCtx),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Installed Version',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      'v$currentVersion+$currentBuildNumber (Windows)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You are running the latest official Windows desktop release.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 10),
              Text(
                'Automatic in-app updates are enabled. New updates will download and install with a single click.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showMobileUpdateAvailableBanner(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('A new TindaKo update is available.'),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'UPDATE NOW',
          textColor: AppTheme.accentOrange,
          onPressed: () {
            UpdateProgressDialog.show(context, _updater);
          },
        ),
        backgroundColor: AppTheme.cardDark,
        duration: const Duration(seconds: 12),
      ),
    );
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

class _DesktopUpdateInfo {
  final String version;
  final int? buildNumber;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  _DesktopUpdateInfo({
    required this.version,
    this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
  });
}
