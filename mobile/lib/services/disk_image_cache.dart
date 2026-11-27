import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persistent local disk cache for cloud product and store images.
///
/// Downloads each unique image URL at most once per device (using existing
/// `dio` + `path_provider` with zero new native plugins, keeping Shorebird
/// OTA patches fully compatible) and serves subsequent loads directly from
/// local storage—eliminating repeated Render image-proxy bandwidth across
/// app restarts.
class DiskImageCache {
  DiskImageCache._();
  static final DiskImageCache instance = DiskImageCache._();

  static const int _maxCachedFiles = 150;
  static const int _maxImageBytes = 6 * 1024 * 1024; // 6 MB safety cap

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.bytes,
    ),
  );

  final Map<String, File> _memoryIndex = {};
  final Map<String, Future<File?>> _inFlight = {};
  Directory? _cacheDir;
  Future<List<int>?> Function(String url)? _customFetcher;

  @visibleForTesting
  void configureForTesting({
    required Directory cacheDir,
    Future<List<int>?> Function(String url)? fetcher,
  }) {
    _cacheDir = cacheDir;
    _customFetcher = fetcher;
    _memoryIndex.clear();
    _inFlight.clear();
  }

  @visibleForTesting
  void clearMemoryIndex() {
    _memoryIndex.clear();
    _inFlight.clear();
  }

  /// Fast synchronous lookup for images already verified on disk in this session.
  File? getCachedFileSync(String url) {
    final file = _memoryIndex[url];
    if (file != null && file.existsSync()) return file;
    _memoryIndex.remove(url);
    return null;
  }

  /// Resolves [url] to a locally cached [File], downloading once if absent.
  /// Returns `null` when caching is unavailable (e.g., web or offline error).
  Future<File?> resolve(String url) {
    if (kIsWeb) return Future.value(null);

    final existing = getCachedFileSync(url);
    if (existing != null) return Future.value(existing);

    return _inFlight[url] ??= _resolveInternal(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<Directory?> _ensureCacheDir() async {
    if (_cacheDir != null) {
      if (!_cacheDir!.existsSync()) {
        await _cacheDir!.create(recursive: true);
      }
      return _cacheDir;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(p.join(tempDir.path, 'tindako_img_cache'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Deterministic, collision-resistant filename derived from [url] (FNV-1a 64-bit).
  String _fileNameForUrl(String url) {
    BigInt hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final unit in url.codeUnits) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }

    String ext = '.img';
    try {
      final pathPart = Uri.parse(url).path;
      final candidate = p.extension(pathPart).toLowerCase();
      if (const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(candidate)) {
        ext = candidate;
      }
    } catch (_) {}

    return '${hash.toRadixString(16).padLeft(16, '0')}$ext';
  }

  Future<File?> _resolveInternal(String url) async {
    final dir = await _ensureCacheDir();
    if (dir == null) return null;

    final target = File(p.join(dir.path, _fileNameForUrl(url)));
    if (target.existsSync()) {
      try {
        if (target.lengthSync() > 0) {
          _memoryIndex[url] = target;
          return target;
        }
      } catch (_) {}
    }

    try {
      final List<int>? bytes;
      if (_customFetcher != null) {
        bytes = await _customFetcher!(url);
      } else {
        final response = await _dio.get<List<int>>(url);
        if (response.statusCode != 200 || response.data == null) {
          return null;
        }
        bytes = response.data;
      }

      if (bytes == null || bytes.isEmpty || bytes.length > _maxImageBytes) {
        return null;
      }

      // Atomic write via temp file so interrupted downloads never leave corrupt images
      final tmp = File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (target.existsSync()) {
        await target.delete();
      }
      final saved = await tmp.rename(target.path);
      _memoryIndex[url] = saved;
      unawaited(_pruneIfNeeded(dir));
      return saved;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pruneIfNeeded(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp'))
          .toList();
      if (files.length <= _maxCachedFiles) return;

      files.sort((a, b) {
        final aMod = a.statSync().modified;
        final bMod = b.statSync().modified;
        return aMod.compareTo(bMod);
      });

      final removeCount = files.length - _maxCachedFiles;
      for (int i = 0; i < removeCount; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

/// Renders a network image via [DiskImageCache] (local file once downloaded),
/// falling back gracefully to [Image.network] or [errorBuilder] if disk
/// caching is unavailable.
class CachedCloudImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final double spinnerSize;
  final Widget Function(BuildContext context) errorBuilder;

  const CachedCloudImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.spinnerSize = 20,
    required this.errorBuilder,
  });

  @override
  State<CachedCloudImage> createState() => _CachedCloudImageState();
}

class _CachedCloudImageState extends State<CachedCloudImage> {
  File? _cachedFile;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _initLookup();
  }

  @override
  void didUpdateWidget(covariant CachedCloudImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initLookup();
    }
  }

  void _initLookup() {
    final syncFile = DiskImageCache.instance.getCachedFileSync(widget.url);
    if (syncFile != null) {
      _cachedFile = syncFile;
      _resolved = true;
      return;
    }

    _cachedFile = null;
    _resolved = false;
    final targetUrl = widget.url;
    DiskImageCache.instance.resolve(targetUrl).then((file) {
      if (!mounted || widget.url != targetUrl) return;
      setState(() {
        _cachedFile = file;
        _resolved = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedFile != null) {
      return Image.file(
        _cachedFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        errorBuilder: (context, error, stackTrace) =>
            widget.errorBuilder(context),
      );
    }

    if (!_resolved && !kIsWeb) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Center(
          child: SizedBox(
            width: widget.spinnerSize,
            height: widget.spinnerSize,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      errorBuilder: (context, error, stackTrace) =>
          widget.errorBuilder(context),
    );
  }
}
