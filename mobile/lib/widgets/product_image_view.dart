import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Reusable widget for rendering product images supporting:
/// 1. Cloud Network URLs (API Image Proxy / Cloudflare R2 / S3 / CDN)
/// 2. Local device files (picked from gallery/camera or offline cache)
/// 3. Graceful fallback placeholder when missing or failed
class ProductImageView extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const ProductImageView({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  bool get _isNetworkUrl {
    if (imagePath == null || imagePath!.isEmpty) return false;
    final trimmed = imagePath!.trim().toLowerCase();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  /// Automatically redirect blocked *.r2.dev or /storage/ URLs through API proxy
  String? get _resolvedNetworkUrl {
    if (!_isNetworkUrl) return null;
    var trimmed = imagePath!.trim();

    if (trimmed.startsWith('http://') && (trimmed.contains('onrender.com') || trimmed.contains('pos-system'))) {
      trimmed = trimmed.replaceFirst('http://', 'https://');
    }

    if (trimmed.contains('.r2.dev/products/') || trimmed.contains('/storage/products/')) {
      final filename = trimmed.split('/products/').last;
      return '${ApiService.instance.baseUrl}/media/products/$filename';
    }

    return trimmed;
  }

  String? get _resolvedLocalFilePath {
    if (imagePath == null || imagePath!.isEmpty || _isNetworkUrl) return null;
    if (imagePath!.startsWith('file://')) {
      try {
        return Uri.parse(imagePath!).toFilePath();
      } catch (_) {
        return imagePath!.replaceFirst('file://', '');
      }
    }
    return imagePath;
  }

  int? get _decodeWidth => (width != null && width! > 0) ? (width! * 2).toInt() : 240;
  int? get _decodeHeight => (height != null && height! > 0) ? (height! * 2).toInt() : 240;

  bool get _isLocalFile {
    final path = _resolvedLocalFilePath;
    return path != null && path.isNotEmpty;
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
                width: 20,
                height: 20,
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

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) return placeholder!;
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: (width != null && width! < 40) ? 18 : 26,
          color: Colors.grey.shade400,
        ),
      ),
    );
  }
}

