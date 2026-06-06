import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:nice_downloader/nice_downloader.dart';
import 'package:nice_downloader/src/storage/download_record.dart'
    show DownloadRecordAdapter, downloadRecordTypeId;

import 'fakes.dart';

void main() {
  late Directory tempDir;
  late InMemoryDownloadRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nice_segmented_test');
    repository = InMemoryDownloadRepository();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  DownloadManager managerWith(
    DownloadClient client, {
    SegmentPlanner planner =
        const DefaultSegmentPlanner(maxSegments: 4, minSegmentSize: 1024),
    RetryPolicy retryPolicy = const NoRetryPolicy(),
    Duration connectionStagger = Duration.zero,
  }) {
    return DownloadManager(
      config: DownloadConfig(
        client: client,
        repository: repository,
        connectivityChecker: const AlwaysOnlineConnectivityChecker(),
        retryPolicy: retryPolicy,
        segmentPlanner: planner,
        progressInterval: Duration.zero,
        connectionStagger: connectionStagger,
      ),
    );
  }

  Future<DownloadStatus> waitForFinish(DownloadTask task) async {
    if (task.status.isFinished) return task.status;
    return (await task.progressStream
            .firstWhere((progress) => progress.status.isFinished))
        .status;
  }

  List<int> bytes(int length) => List.generate(length, (i) => i % 251);

  group('DefaultSegmentPlanner', () {
    test('splits evenly, last segment absorbs the remainder', () {
      const planner =
          DefaultSegmentPlanner(maxSegments: 4, minSegmentSize: 10);
      final segments = planner.plan(start: 0, endExclusive: 103);

      expect(segments, hasLength(4));
      expect(segments.first.start, 0);
      expect(segments.last.end, 102);
      // Contiguous, no gaps or overlaps.
      for (var i = 1; i < segments.length; i++) {
        expect(segments[i].start, segments[i - 1].end + 1);
      }
      expect(segments.fold(0, (sum, s) => sum + s.length), 103);
    });

    test('stays single-stream below 2x minSegmentSize', () {
      const planner =
          DefaultSegmentPlanner(maxSegments: 8, minSegmentSize: 100);
      expect(planner.plan(start: 0, endExclusive: 199), hasLength(1));
      expect(planner.plan(start: 0, endExclusive: 200), hasLength(2));
    });

    test('caps at maxSegments', () {
      const planner =
          DefaultSegmentPlanner(maxSegments: 3, minSegmentSize: 1);
      expect(planner.plan(start: 0, endExclusive: 1000), hasLength(3));
    });

    test('plans a sub-range (resume of a single-stream download)', () {
      const planner =
          DefaultSegmentPlanner(maxSegments: 2, minSegmentSize: 10);
      final segments = planner.plan(start: 50, endExclusive: 100);
      expect(segments, hasLength(2));
      expect(segments.first.start, 50);
      expect(segments.last.end, 99);
    });
  });

  group('segmented downloads', () {
    test('downloads in parallel segments and writes exact bytes', () async {
      final content = bytes(10 * 1024);
      final client = FakeDownloadClient(content, chunkSize: 256);
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/big',
        directory: tempDir.path,
        fileName: 'segmented',
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);

      // 1 probe + 4 segment connections.
      expect(client.openCalls, 5);
      // The 4 segment requests cover the whole file contiguously.
      final segmentRanges = client.requestedRanges
          .where((r) => r.end != null)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      expect(segmentRanges, hasLength(4));
      expect(segmentRanges.first.start, 0);
      expect(segmentRanges.last.end, content.length - 1);

      expect(task.progress.downloadedBytes, content.length);
      expect(task.progress.percent, 100);
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('falls back to single stream when server lacks range support',
        () async {
      final content = bytes(8 * 1024);
      final client = FakeDownloadClient(content, supportsResume: false);
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/no-ranges',
        directory: tempDir.path,
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);
      expect(client.openCalls, 1); // probe connection was reused
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('small files stay single-stream', () async {
      final client = FakeDownloadClient(bytes(512));
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/small',
        directory: tempDir.path,
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);
      expect(client.openCalls, 1);
    });

    test('pause persists per-segment state, resume completes', () async {
      final content = bytes(16 * 1024);
      final client = FakeDownloadClient(content, chunkSize: 64);
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/pausable',
        directory: tempDir.path,
        fileName: 'seg_pause',
      );

      final reachedSome = Completer<void>();
      task.progressStream.listen((progress) {
        if (!reachedSome.isCompleted && progress.downloadedBytes >= 2048) {
          reachedSome.complete();
        }
      });

      await task.start();
      await reachedSome.future;
      await task.pause();

      expect(task.status, DownloadStatus.paused);
      expect(task.progress.downloadedBytes, lessThan(content.length));

      final record = await repository.find('https://example.com/pausable');
      expect(record!.segments, isNotNull);
      expect(
        record.segments!.fold(0, (sum, s) => sum + s.downloaded),
        task.progress.downloadedBytes,
      );

      await task.resume();
      expect(await waitForFinish(task), DownloadStatus.completed);
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('resumes a segmented download across sessions', () async {
      final content = bytes(16 * 1024);
      const url = 'https://example.com/cross-session';

      // Session 1: download partially, then pause.
      final client1 = FakeDownloadClient(content, chunkSize: 64);
      final task1 = await managerWith(client1).createDownload(
        url: url,
        directory: tempDir.path,
        fileName: 'session',
      );
      final reachedSome = Completer<void>();
      task1.progressStream.listen((progress) {
        if (!reachedSome.isCompleted && progress.downloadedBytes >= 2048) {
          reachedSome.complete();
        }
      });
      await task1.start();
      await reachedSome.future;
      await task1.pause();
      final resumedFrom = task1.progress.downloadedBytes;
      await task1.dispose();

      // Session 2: fresh manager + task, same repository.
      final client2 = FakeDownloadClient(content, chunkSize: 64);
      final task2 = await managerWith(client2).createDownload(
        url: url,
        directory: tempDir.path,
      );
      await task2.start();
      expect(await waitForFinish(task2), DownloadStatus.completed);

      // It resumed — did not redownload the bytes from session 1.
      final downloadedInSession2 = client2.requestedRanges
          .where((r) => r.end != null)
          .fold(0, (sum, r) => sum + (r.end! - r.start + 1));
      expect(downloadedInSession2, content.length - resumedFrom);
      expect(await File(task2.filePath!).readAsBytes(), content);
    });

    test('cancel deletes the pre-allocated file and the record', () async {
      final content = bytes(16 * 1024);
      final client = FakeDownloadClient(content, chunkSize: 64);
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/cancelable',
        directory: tempDir.path,
        fileName: 'seg_cancel',
      );

      final gotBytes = Completer<void>();
      task.progressStream.listen((progress) {
        if (!gotBytes.isCompleted && progress.downloadedBytes > 0) {
          gotBytes.complete();
        }
      });

      await task.start();
      await gotBytes.future;
      final path = task.filePath!;
      await task.cancel();

      expect(task.status, DownloadStatus.canceled);
      expect(await File(path).exists(), isFalse);
      expect(await repository.find('https://example.com/cancelable'), isNull);
    });

    test('a dropped segment retries alone and the download completes',
        () async {
      final content = bytes(8 * 1024);
      final client = FakeDownloadClient(content, chunkSize: 128)
        ..failAfterBytes = 256; // first stream to deliver 256 bytes drops once
      final manager = managerWith(
        client,
        retryPolicy: const ExponentialBackoffRetryPolicy(
            maxRetries: 2, baseDelay: Duration(milliseconds: 1)),
      );
      final task = await manager.createDownload(
        url: 'https://example.com/flaky-segment',
        directory: tempDir.path,
        fileName: 'seg_flaky',
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('NoSegmentationPlanner forces single-stream', () async {
      final client = FakeDownloadClient(bytes(10 * 1024));
      final manager =
          managerWith(client, planner: const NoSegmentationPlanner());
      final task = await manager.createDownload(
        url: 'https://example.com/forced-single',
        directory: tempDir.path,
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);
      expect(client.openCalls, 1);
    });

    test('a corrupted segment is detected and only it is redownloaded',
        () async {
      final content = bytes(16 * 1024);
      const url = 'https://example.com/tampered-segment';
      final client = FakeDownloadClient(content, chunkSize: 64);
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: url,
        directory: tempDir.path,
        fileName: 'seg_tampered',
      );

      final reachedSome = Completer<void>();
      task.progressStream.listen((p) {
        if (!reachedSome.isCompleted && p.downloadedBytes >= 4096) {
          reachedSome.complete();
        }
      });
      await task.start();
      await reachedSome.future;
      await task.pause();

      // The user edits bytes inside one segment's downloaded region.
      final record = await repository.find(url);
      final victim =
          record!.segments!.firstWhere((s) => s.downloaded > 100);
      final raf = await File(task.filePath!).open(mode: FileMode.append);
      await raf.setPosition(victim.start + 50);
      await raf.writeFrom([0xFF, 0xFF, 0xFF]);
      await raf.close();

      await task.resume();
      expect(await waitForFinish(task), DownloadStatus.completed);
      // The damaged segment was reset and re-requested from its own start
      // (once on the initial run + once after verification failed).
      final restarts = client.requestedRanges
          .where((r) => r.start == victim.start && r.end == victim.end)
          .length;
      expect(restarts, 2);
      // Final file is byte-exact despite the tampering.
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('adapts to a rate-limiting server by reducing connections (429)',
        () async {
      final content = bytes(8 * 1024);
      // Server allows only 2 concurrent connections per IP — like Hetzner.
      final client = FakeDownloadClient(
        content,
        chunkSize: 128,
        maxConcurrentConnections: 2,
        chunkDelay: const Duration(milliseconds: 2),
      );
      final manager = managerWith(client);
      final task = await manager.createDownload(
        url: 'https://example.com/rate-limited',
        directory: tempDir.path,
        fileName: 'rate_limited',
      );

      await task.start();
      expect(await waitForFinish(task), DownloadStatus.completed);

      // The server did reject extra connections, and the task recovered by
      // halving its concurrency instead of failing.
      expect(client.rejectedWith429, greaterThan(0));
      expect(await File(task.filePath!).readAsBytes(), content);
    });

    test('Hive adapter round-trips records with and without segments',
        () async {
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(downloadRecordTypeId)) {
        Hive.registerAdapter(DownloadRecordAdapter());
      }
      final box = await Hive.openBox<DownloadRecord>('adapter_test');
      addTearDown(() => box.deleteFromDisk());

      final segmented = DownloadRecord(
        url: 'https://example.com/segmented',
        filePath: 'C:/downloads/file.bin',
        totalBytes: 1000,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        segments: const [
          SegmentProgress(start: 0, end: 499, downloaded: 500, crc32: 0xCAFE),
          SegmentProgress(start: 500, end: 999, downloaded: 100),
        ],
      );
      final singleStream = DownloadRecord(
        url: 'https://example.com/single',
        filePath: 'C:/downloads/other.bin',
        totalBytes: 42,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        downloadedBytes: 17,
        crc32: 0xBEEF,
      );
      await box.put(segmented.url, segmented);
      await box.put(singleStream.url, singleStream);
      await box.flush();

      final readSegmented = box.get(segmented.url)!;
      expect(readSegmented.totalBytes, 1000);
      expect(readSegmented.segments, hasLength(2));
      expect(readSegmented.segments![0].downloaded, 500);
      expect(readSegmented.segments![0].crc32, 0xCAFE);
      expect(readSegmented.segments![1].start, 500);
      final readSingle = box.get(singleStream.url)!;
      expect(readSingle.segments, isNull);
      expect(readSingle.downloadedBytes, 17);
      expect(readSingle.crc32, 0xBEEF);
    });
  });
}
