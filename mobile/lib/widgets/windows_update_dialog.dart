import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../core/app_theme.dart';

/// Interactive modal dialog for downloading and applying single-click Windows desktop updates.
class WindowsUpdateDialog extends StatefulWidget {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool forceUpdate;

  const WindowsUpdateDialog({
    super.key,
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    this.forceUpdate = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String version,
    required String downloadUrl,
    required String releaseNotes,
    bool forceUpdate = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (_) => WindowsUpdateDialog(
        version: version,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        forceUpdate: forceUpdate,
      ),
    );
  }

  @override
  State<WindowsUpdateDialog> createState() => _WindowsUpdateDialogState();
}

class _WindowsUpdateDialogState extends State<WindowsUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;
  CancelToken? _cancelToken;

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _statusText = 'Connecting to update server...';
      _errorMessage = null;
    });

    _cancelToken = CancelToken();

    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}\\TindaKo-Setup-Update.exe';

      // Delete any previous temporary setup file
      final tempFile = File(savePath);
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      final dio = Dio();
      await dio.download(
        widget.downloadUrl,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            final percent = received / total;
            final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = percent.clamp(0.0, 1.0);
              _statusText = 'Downloading update... $receivedMB MB / $totalMB MB (${(_progress * 100).toInt()}%)';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _progress = 1.0;
        _statusText = 'Launching installer... TindaKo will restart in a moment.';
      });

      await Future.delayed(const Duration(milliseconds: 600));

      // Verify downloaded installer binary is valid (> 1 MB)
      final downloadedFile = File(savePath);
      if (await downloadedFile.exists() && (await downloadedFile.length()) > 1024 * 1024) {
        // Launch installer silently in detached mode
        await Process.start(
          savePath,
          ['/SILENT', '/FORCECLOSEAPPLICATIONS'],
          mode: ProcessStartMode.detached,
        );

        // Terminate running Flutter instance so Inno Setup can overwrite application files
        exit(0);
      } else {
        throw 'Downloaded setup file appears to be corrupted or incomplete.';
      }
    } catch (e) {
      if (!mounted) return;
      if (CancelToken.isCancel(e as dynamic)) return;

      setState(() {
        _isDownloading = false;
        _errorMessage = 'Could not download update: ${e.toString().replaceAll('Exception:', '')}';
      });
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentOrange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: AppTheme.accentOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'New Update Available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderColor(context)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('New Version', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  Text(
                    'v${widget.version}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentOrange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (widget.releaseNotes.isNotEmpty) ...[
              Text(
                widget.releaseNotes,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentOrange),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accentRose.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppTheme.accentRose, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: AppTheme.accentRose),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isDownloading && _errorMessage == null)
              Text(
                'Updating is automatic and takes a few seconds. Your store login, products, and offline records will remain completely intact.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!_isDownloading && !widget.forceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
        if (!_isDownloading)
          ElevatedButton.icon(
            onPressed: _startDownloadAndInstall,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_errorMessage != null ? 'Retry Update' : 'Update Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
      ],
    );
  }
}

