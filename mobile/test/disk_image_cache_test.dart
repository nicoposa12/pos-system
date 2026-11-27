import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindako/services/disk_image_cache.dart';

void main() {
  test('DiskImageCache downloads once, deduplicates concurrent calls, and serves from disk after memory clear', () async {
    final tempDir = await Directory.systemTemp.createTemp('tindako_img_test_');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    int networkFetchCount = 0;
    const sampleUrl = 'https://pos-system-1-y58u.onrender.com/api/media/products/abc123.png';
    final fakePngBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4];

    DiskImageCache.instance.configureForTesting(
      cacheDir: tempDir,
      fetcher: (url) async {
        networkFetchCount++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return fakePngBytes;
      },
    );

    // Concurrent calls for the same URL must trigger only 1 network request
    final concurrent = await Future.wait([
      DiskImageCache.instance.resolve(sampleUrl),
      DiskImageCache.instance.resolve(sampleUrl),
      DiskImageCache.instance.resolve(sampleUrl),
    ]);

    expect(networkFetchCount, 1);
    expect(concurrent[0], isNotNull);
    expect(concurrent[0]!.existsSync(), isTrue);
    expect(concurrent[0]!.readAsBytesSync(), fakePngBytes);
    expect(DiskImageCache.instance.getCachedFileSync(sampleUrl), isNotNull);

    // Simulate app restart by clearing in-memory index; disk cache must still hit with 0 fetches
    DiskImageCache.instance.clearMemoryIndex();
    expect(DiskImageCache.instance.getCachedFileSync(sampleUrl), isNull);

    final afterRestart = await DiskImageCache.instance.resolve(sampleUrl);
    expect(networkFetchCount, 1); // still 1 — served from disk!
    expect(afterRestart, isNotNull);
    expect(afterRestart!.readAsBytesSync(), fakePngBytes);
  });
}
