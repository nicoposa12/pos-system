import 'dart:io';
import 'package:flutter/material.dart';

/// Reusable widget for rendering product images supporting:
/// 1. Cloud Network URLs (Cloudflare R2 / S3 / CDN)
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

  bool get _isLocalFile {
    if (imagePath == null || imagePath!.isEmpty) return false;
    if (_isNetworkUrl) return false;
    try {
      return File(imagePath!).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isNetworkUrl) {
      content = Image.network(
        imagePath!.trim(),
        width: width,
        height: height,
        fit: fit,
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
        File(imagePath!),
        width: width,
        height: height,
        fit: fit,
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

