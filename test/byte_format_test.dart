import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_downloader/nice_downloader.dart';

void main() {
  group('formatBytes', () {
    test('formats plain bytes', () {
      expect(512.readableSize.toString(), '512.0 B');
    });

    test('formats kilobytes', () {
      expect(1536.readableSize.value, 1.5);
      expect(1536.readableSize.unit, 'KB');
    });

    test('formats megabytes', () {
      expect((5 * 1024 * 1024).readableSize.toString(), '5.0 MB');
    });

    test('formats gigabytes', () {
      expect((3 * 1024 * 1024 * 1024).readableSize.unit, 'GB');
    });

    test('formats speed with /s suffix', () {
      expect((2.0 * 1024 * 1024).readableSpeed.toString(), '2.0 MB/s');
    });
  });

  group('DownloadProgress', () {
    test('percent is 0 when total is unknown', () {
      const progress = DownloadProgress.initial();
      expect(progress.percent, 0);
    });

    test('percent is computed and clamped', () {
      const progress = DownloadProgress(
        status: DownloadStatus.downloading,
        downloadedBytes: 250,
        totalBytes: 1000,
      );
      expect(progress.percent, 25);
    });

    test('copyWith returns a new instance and can clear the speed', () {
      const original = DownloadProgress(
        status: DownloadStatus.downloading,
        downloadedBytes: 10,
        totalBytes: 100,
        bytesPerSecond: 1024,
      );
      final updated = original.copyWith(bytesPerSecond: null);

      expect(identical(original, updated), isFalse);
      expect(original.bytesPerSecond, 1024); // untouched — truly immutable
      expect(updated.bytesPerSecond, isNull);
    });
  });

  group('ExponentialBackoffRetryPolicy', () {
    test('grows the delay and gives up after maxRetries', () {
      const policy = ExponentialBackoffRetryPolicy(
        maxRetries: 3,
        baseDelay: Duration(seconds: 1),
      );
      expect(policy.delayBeforeRetry(1, 'e'), const Duration(seconds: 1));
      expect(policy.delayBeforeRetry(2, 'e'), const Duration(seconds: 2));
      expect(policy.delayBeforeRetry(3, 'e'), const Duration(seconds: 4));
      expect(policy.delayBeforeRetry(4, 'e'), isNull);
    });

    test('honors Retry-After when the server rate-limits (429)', () {
      const policy = ExponentialBackoffRetryPolicy(
        maxRetries: 3,
        baseDelay: Duration(seconds: 1),
      );
      const rateLimited =
          ServerException(429, retryAfter: Duration(seconds: 30));
      // The server's requested wait wins over the shorter backoff…
      expect(policy.delayBeforeRetry(1, rateLimited),
          const Duration(seconds: 30));
      // …but the retry budget still applies.
      expect(policy.delayBeforeRetry(4, rateLimited), isNull);
      // A Retry-After shorter than the computed backoff is ignored.
      const briefly = ServerException(429, retryAfter: Duration(seconds: 1));
      expect(
          policy.delayBeforeRetry(3, briefly), const Duration(seconds: 4));
    });
  });

  group('parseRetryAfter', () {
    test('parses delta-seconds', () {
      expect(parseRetryAfter('120'), const Duration(seconds: 120));
      expect(parseRetryAfter(' 5 '), const Duration(seconds: 5));
    });

    test('parses an HTTP date', () {
      final date = HttpDate.format(
          DateTime.now().toUtc().add(const Duration(seconds: 60)));
      final parsed = parseRetryAfter(date);
      expect(parsed, isNotNull);
      expect(parsed!.inSeconds, inInclusiveRange(55, 60));
    });

    test('returns null for missing or malformed values', () {
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter('soon'), isNull);
      expect(parseRetryAfter('-3'), isNull);
    });
  });
}
