import 'package:flutter_test/flutter_test.dart';
import 'package:nice_downloader/nice_downloader.dart';

void main() {
  group('BandwidthThrottle', () {
    test('unlimited (null) never asks for a pause', () {
      final throttle = BandwidthThrottle();
      for (var i = 0; i < 100; i++) {
        expect(throttle.consume(1024 * 1024), isNull);
      }
    });

    test('consuming far over the rate returns a proportional delay', () {
      final throttle = BandwidthThrottle(bytesPerSecond: 1000);
      // First call grants a one-second burst (1000 bytes) for free.
      expect(throttle.consume(1000), isNull);
      // 2000 bytes over budget at 1000 B/s → ~2 seconds of pause.
      final delay = throttle.consume(2000)!;
      expect(delay.inMilliseconds, closeTo(2000, 100));
    });

    test('small chunks within the rate are not delayed', () {
      final throttle = BandwidthThrottle(bytesPerSecond: 1024 * 1024);
      expect(throttle.consume(1024), isNull);
      expect(throttle.consume(1024), isNull);
    });

    test('limit can be changed and removed at runtime', () {
      final throttle = BandwidthThrottle(bytesPerSecond: 100);
      throttle.consume(100);
      expect(throttle.consume(500), isNotNull);

      throttle.bytesPerSecond = null; // back to max speed
      expect(throttle.consume(10 * 1024 * 1024), isNull);

      throttle.bytesPerSecond = 100;
      expect(throttle.consume(1000), isNotNull);
    });
  });

  test('DownloadTask exposes a mutable speedLimit', () async {
    final manager = DownloadManager(
      config: DownloadConfig(
        repository: InMemoryDownloadRepository(),
        speedLimit: 512 * 1024,
      ),
    );
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: 'irrelevant',
    );
    expect(task.speedLimit, 512 * 1024);

    task.speedLimit = null; // max speed
    expect(task.speedLimit, isNull);

    final override = await manager.createDownload(
      url: 'https://example.com/other',
      directory: 'irrelevant',
      speedLimit: 1024,
    );
    expect(override.speedLimit, 1024);
  });
}
