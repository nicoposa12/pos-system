import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Reusable widget for rendering store and business storefront/logo photos.
/// Supports:
/// 1. Cloud Network URLs (Cloudflare R2 / S3 / API media proxy)
/// 2. Local device files (picked from gallery/camera before upload or during offline caching)
/// 3. Graceful fallback placeholder (branded store icon or initials with theme-adaptive styling)
class StoreImageView extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final Color? fallbackBgColor;
  final Widget? customPlaceholder;

  const StoreImageView({
    super.key,
    required this.imagePath,
    this.width = 44,
    this.height = 44,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.store_rounded,
    this.fallbackColor,
    this.fallbackBgColor,
    this.customPlaceholder,
  });

  bool get _isNetworkUrl {
    if (imagePath == null || imagePath!.trim().isEmpty) return false;
    final trimmed = imagePath!.trim().toLowerCase();
    return trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('/media/stores/') ||
        trimmed.startsWith('media/stores/') ||
        trimmed.startsWith('/storage/stores/') ||
        trimmed.startsWith('storage/stores/');
  }

  /// Automatically redirect blocked *.r2.dev or /storage/ URLs through API proxy
  String? get _resolvedNetworkUrl {
    if (!_isNetworkUrl) return null;
    final trimmed = imagePath!.trim();

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      var url = trimmed;
      if (url.startsWith('http://') && (url.contains('onrender.com') || url.contains('pos-system'))) {
        url = url.replaceFirst('http://', 'https://');
      }
      if (url.contains('.r2.dev/stores/') ||
          url.contains('/storage/stores/')) {
        final filename = url.split('/stores/').last;
        return '${ApiService.instance.baseUrl}/media/stores/$filename';
      }
      return url;
    }

    // Relative path handling
    final filename = trimmed.split('/stores/').last;
    return '${ApiService.instance.baseUrl}/media/stores/$filename';
  }

  String? get _resolvedLocalFilePath {
      if (imagePath == null || imagePath!.trim().isEmpty || _isNetworkUrl) {
        return null;
      }
    final trimmed = imagePath!.trim();
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath();
      } catch (_) {
        return trimmed.replaceFirst('file://', '');
      }
    }
    return trimmed;
  }

  int? get _decodeWidth =>
      (width != null && width! > 0) ? (width! * 2).toInt() : 180;
  int? get _decodeHeight =>
      (height != null && height! > 0) ? (height! * 2).toInt() : 180;

  bool get _isLocalFile {
    final path = _resolvedLocalFilePath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    final networkUrl = _resolvedNetworkUrl;
    if (networkUrl != null) {
      content = Image.network(
        networkUrl,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: _decodeWidth,
        cacheHeight: _decodeHeight,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context),
      );
    } else if (_isLocalFile) {
      content = Image.file(
        File(_resolvedLocalFilePath!),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: _decodeWidth,
        cacheHeight: _decodeHeight,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context),
      );
    } else {
      content = _buildPlaceholder(context);
    }

    final radius = borderRadius ?? BorderRadius.circular(10);
    return ClipRRect(borderRadius: radius, child: content);
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (customPlaceholder != null) return customPlaceholder!;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = fallbackColor ?? const Color(0xFF059669);
    final bgColor =
        fallbackBgColor ??
        (isDark
            ? color.withValues(alpha: 0.22)
            : color.withValues(alpha: 0.12));

    final iconSize = (width != null && width! > 0)
        ? (width! * 0.48).clamp(16.0, 32.0)
        : 22.0;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius ?? BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.20),
          width: 0.8,
        ),
      ),
      child: Center(
        child: Icon(fallbackIcon, size: iconSize, color: color),
      ),
    );
  }
}
