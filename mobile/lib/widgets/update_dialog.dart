import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../core/app_theme.dart';

/// Modal dialog that gives users the choice to update now or later,
/// and displays live percentage progress while downloading and
/// installing Shorebird over-the-air patches.
class UpdateProgressDialog extends StatefulWidget {
  final ShorebirdUpdater updater;
  final VoidCallback? onCompleted;
  final bool autoStart;

  const UpdateProgressDialog({
    super.key,
    required this.updater,
    this.onCompleted,
    this.autoStart = false,
  });

  /// Displays the update dialog and allows the user to decide to update now or later.
  static Future<bool> show(
    BuildContext context,
    ShorebirdUpdater updater, {
    bool autoStart = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateProgressDialog(
        updater: updater,
        autoStart: autoStart,
      ),
    );
    return result ?? false;
  }

  @override
  State<UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<UpdateProgressDialog>
    with SingleTickerProviderStateMixin {
  late bool _isDownloading;
  double _progress = 0.05;
  bool _isDone = false;
  String? _errorMessage;
  Timer? _progressSimulationTimer;

  @override
  void initState() {
    super.initState();
    _isDownloading = widget.autoStart;
    if (widget.autoStart) {
      _startDownload();
    }
  }

  @override
  void dispose() {
    _progressSimulationTimer?.cancel();
    super.dispose();
  }

  void _startDownload() {
    setState(() {
      _errorMessage = null;
      _progress = 0.05;
      _isDone = false;
    });

    // Patches are compact binary diffs (~1MB - 2MB).
    // Simulate smooth progress progression while the native Shorebird updater downloads and links the patch.
    _progressSimulationTimer?.cancel();
    _progressSimulationTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (!mounted || _isDone || _errorMessage != null) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_progress < 0.85) {
          _progress += 0.04;
        } else if (_progress < 0.96) {
          _progress += 0.01;
        }
      });
    });

    widget.updater.update().then((_) {
      _progressSimulationTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _progress = 1.0;
        _isDone = true;
      });
      widget.onCompleted?.call();
    }).catchError((e) {
      _progressSimulationTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _errorMessage = e is UpdateException
            ? 'Update failed (${e.reason.name}). Please try again later.'
            : 'Could not complete update. Continuing with current version.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percentInt = (_progress * 100).toInt().clamp(0, 100);

    return PopScope(
      canPop: !_isDownloading || _isDone || _errorMessage != null,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Theme.of(context).cardTheme.color ??
            (isDark ? const Color(0xFF1E222D) : Colors.white),
        elevation: 16,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header Icon with Glow ──
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: _isDone
                        ? const LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF10B981)],
                          )
                        : (_errorMessage != null
                            ? const LinearGradient(
                                colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                              )
                            : AppTheme.orangeGradient),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (_isDone
                                ? const Color(0xFF10B981)
                                : (_errorMessage != null
                                    ? const Color(0xFFEF4444)
                                    : AppTheme.accentOrange))
                            .withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isDone
                        ? Icons.check_circle_rounded
                        : (_errorMessage != null
                            ? Icons.error_outline_rounded
                            : Icons.system_update_rounded),
                    color: Colors.white,
                    size: 32,
                  ),
                ),

                const SizedBox(height: 20),

                // ── Title ──
                Text(
                  _isDone
                      ? 'Update Ready!'
                      : (_errorMessage != null
                          ? 'Update Interrupted'
                          : (_isDownloading
                              ? 'Updating TindaKo POS'
                              : 'New Update Available')),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 8),

                // ── Subtitle / Details ──
                Text(
                  _isDone
                      ? 'The latest cloud improvements have been downloaded and installed.'
                      : (_errorMessage != null
                          ? _errorMessage!
                          : (_isDownloading
                              ? 'Downloading latest cloud features and enhancements. Please keep the app open.'
                              : 'A new cloud update (patch) is available for TindaKo POS with performance fixes and improvements.')),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.mutedText(context),
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 20),

                // ── Content depending on State ──
                if (!_isDownloading && !_isDone && _errorMessage == null) ...[
                  // Information card for deciding
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: AppTheme.accentTeal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Updating takes just a few seconds. Your store products, orders, and offline data will remain completely intact.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // "Later" and "Update Now" Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Later',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.mutedText(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isDownloading = true;
                            });
                            _startDownload();
                          },
                          icon: const Icon(Icons.download_rounded,
                              size: 18, color: Colors.white),
                          label: const Text(
                            'Update Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOrange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_isDownloading && !_isDone && _errorMessage == null) ...[
                  // ── Progress Bar & Percentage ──
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 10,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accentOrange,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Patching core files...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mutedText(context),
                        ),
                      ),
                      Text(
                        '$percentInt%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.accentOrange,
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ] else if (_isDone) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.accentTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.accentTeal.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.restart_alt_rounded,
                            color: AppTheme.accentTeal, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Restart TindaKo to activate the new version.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentTeal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        // Close the app so user can relaunch with new patch applied
                        SystemNavigator.pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Restart App Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'Restart Later',
                      style: TextStyle(
                        color: AppTheme.mutedText(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else if (_errorMessage != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Continue to App'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _errorMessage = null;
                              _isDownloading = true;
                            });
                            _startDownload();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOrange,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Retry Update',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
