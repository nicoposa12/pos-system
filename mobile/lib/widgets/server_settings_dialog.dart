import 'package:flutter/material.dart';
import '../core/app_theme.dart';
import '../services/api_service.dart';

Future<void> showServerSettingsDialog(
  BuildContext context, {
  VoidCallback? onUrlChanged,
}) async {
  final currentUrl = ApiService.instance.baseUrl;
  final urlController = TextEditingController(text: currentUrl);

  bool isTesting = false;
  bool? testSuccess;
  String? testMessage;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppTheme.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.borderDark),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.dns_rounded,
                color: AppTheme.accentOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Server Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Configure the API endpoint used for online sales, PIN login, and data updates.',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Quick Presets
                const Text(
                  'QUICK PRESETS',
                  style: TextStyle(
                    color: AppTheme.textSecondaryDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip(
                      label: 'Render Cloud',
                      url: 'https://pos-system-1-y58u.onrender.com/api',
                      controller: urlController,
                      onSelected: () => setDialogState(() {
                        testSuccess = null;
                        testMessage = null;
                      }),
                    ),
                    _presetChip(
                      label: 'Android Emulator',
                      url: 'http://10.0.2.2:8000/api',
                      controller: urlController,
                      onSelected: () => setDialogState(() {
                        testSuccess = null;
                        testMessage = null;
                      }),
                    ),
                    _presetChip(
                      label: 'Localhost',
                      url: 'http://127.0.0.1:8000/api',
                      controller: urlController,
                      onSelected: () => setDialogState(() {
                        testSuccess = null;
                        testMessage = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // URL Input Field
                TextField(
                  controller: urlController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    labelText: 'API Base URL',
                    labelStyle: const TextStyle(
                      color: AppTheme.textSecondaryDark,
                      fontSize: 12,
                    ),
                    hintText: 'https://your-api.onrender.com/api',
                    hintStyle: TextStyle(
                      color: AppTheme.textSecondaryDark.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceDark,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderDark),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderDark),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.accentOrange,
                        width: 1.5,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: AppTheme.textSecondaryDark,
                      ),
                      onPressed: () => setDialogState(() {
                        urlController.clear();
                        testSuccess = null;
                        testMessage = null;
                      }),
                    ),
                  ),
                  onChanged: (_) => setDialogState(() {
                    testSuccess = null;
                    testMessage = null;
                  }),
                ),
                const SizedBox(height: 12),

                // Connection Test Action
                InkWell(
                  onTap: isTesting
                      ? null
                      : () async {
                          final testUrl = urlController.text.trim();
                          if (testUrl.isEmpty) return;
                          setDialogState(() {
                            isTesting = true;
                            testSuccess = null;
                            testMessage = null;
                          });
                          final stopwatch = Stopwatch()..start();
                          final ok = await ApiService.instance.checkConnection(
                            testUrl,
                            const Duration(seconds: 60),
                          );
                          stopwatch.stop();

                          setDialogState(() {
                            isTesting = false;
                            testSuccess = ok;
                            testMessage = ok
                                ? 'Server online (${stopwatch.elapsedMilliseconds}ms)'
                                : 'Unable to connect to $testUrl within 60s. Check Render Dashboard to ensure service is live and not Suspended.';
                          });
                        },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: testSuccess == true
                            ? AppTheme.accentTeal.withValues(alpha: 0.6)
                            : testSuccess == false
                                ? AppTheme.accentRose.withValues(alpha: 0.6)
                                : AppTheme.borderDark,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isTesting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accentOrange,
                            ),
                          )
                        else
                          Icon(
                            testSuccess == true
                                ? Icons.check_circle_rounded
                                : testSuccess == false
                                    ? Icons.error_outline_rounded
                                    : Icons.network_check_rounded,
                            size: 18,
                            color: testSuccess == true
                                ? AppTheme.accentTeal
                                : testSuccess == false
                                    ? AppTheme.accentRose
                                    : AppTheme.textSecondaryDark,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isTesting
                                ? 'Connecting to cloud server (waking up service if idle)...'
                                : testMessage ?? 'Tap here to test connection',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: testSuccess == true
                                  ? AppTheme.accentTeal
                                  : testSuccess == false
                                      ? AppTheme.accentRose
                                      : AppTheme.textSecondaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondaryDark),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                await ApiService.instance.setBaseUrl(newUrl);
                onUrlChanged?.call();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Server URL updated to: ${ApiService.instance.baseUrl}',
                      ),
                      backgroundColor: AppTheme.accentTeal,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Save & Apply',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _presetChip({
  required String label,
  required String url,
  required TextEditingController controller,
  required VoidCallback onSelected,
}) {
  final isSelected = controller.text.trim() == url;
  return ActionChip(
    label: Text(label),
    labelStyle: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: isSelected ? Colors.white : AppTheme.textSecondaryDark,
    ),
    backgroundColor: isSelected
        ? AppTheme.accentOrange.withValues(alpha: 0.3)
        : AppTheme.surfaceDark,
    side: BorderSide(
      color: isSelected ? AppTheme.accentOrange : AppTheme.borderDark,
    ),
    onPressed: () {
      controller.text = url;
      onSelected();
    },
  );
}

