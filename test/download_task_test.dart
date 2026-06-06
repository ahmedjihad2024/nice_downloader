import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_downloader/nice_downloader.dart';

import 'fakes.dart';

void main() {
  late Directory tempDir;
  late InMemoryDownloadRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nice_downloader_test');
    repository = InMemoryDownloadRepository();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  DownloadManager managerWith(
    DownloadClient client, {
    List<DownloadInterceptor> interceptors = const [],
    RetryPolicy retryPolicy = const NoRetryPolicy(),
  }) {
    return DownloadManager(
      config: DownloadConfig(
        client: client,
        repository: repository,
        connectivityChecker: const AlwaysOnlineConnectivityChecker(),
        retryPolicy: retryPolicy,
        interceptors: interceptors,
        progressInterval: Duration.zero,
      ),
    );
  }

  Future<DownloadStatus> waitForFinish(DownloadTask task) async {
    if (task.status.isFinished) return task.status;
    return (await task.progressStream
            .firstWhere((progress) => progress.status.isFinished))
        .status;
  }

  List<int> bytes(int length) => List.generate(length, (i) => i % 256);

  test('downloads a file end to end and writes the exact bytes', () async {
    final content = bytes(1000);
    final manager = managerWith(FakeDownloadClient(content));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
      fileName: 'video',
    );

    final statuses = <DownloadStatus>[];
    task.progressStream.listen((progress) => statuses.add(progress.status));

    await task.start();
    expect(await waitForFinish(task), DownloadStatus.completed);

    expect(statuses.first, DownloadStatus.connecting);
    expect(statuses, contains(DownloadStatus.downloading));
    expect(task.progress.downloadedBytes, content.length);
    expect(task.progress.percent, 100);
    expect(task.filePath, endsWith('video.bin'));
    expect(await File(task.filePath!).readAsBytes(), content);
  });

  test('uses server suggested file name when none is given', () async {
    final manager = managerWith(FakeDownloadClient(bytes(10)));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );
    await task.start();
    await waitForFinish(task);
    expect(task.filePath, endsWith('fake_file.bin'));
  });

  test('falls back to the URL file name when the server suggests none',
      () async {
    final client = FakeDownloadClient(bytes(10),
        suggestedFileName: null, fileExtension: null);
    final manager = managerWith(client);
    final task = await manager.createDownload(
      url: 'https://ash-speed.example.com/100MB.bin',
      directory: tempDir.path,
    );
    await task.start();
    await waitForFinish(task);
    expect(task.filePath, endsWith('100MB.bin'));
  });

  test('generic content types are not used as file extensions', () {
    expect(extensionFromContentType('application/octet-stream'), isNull);
    expect(extensionFromContentType('application/x-download'), isNull);
    expect(extensionFromContentType('video/mp4; charset=utf-8'), 'mp4');
    expect(extensionFromContentType(null), isNull);
  });

  test('pause keeps partial file, resume completes it', () async {
    final content = bytes(2048);
    final manager = managerWith(FakeDownloadClient(content, chunkSize: 64));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
      fileName: 'paused',
    );

    final reachedHalf = Completer<void>();
    task.progressStream.listen((progress) {
      if (!reachedHalf.isCompleted && progress.downloadedBytes >= 512) {
        reachedHalf.complete();
      }
    });

    await task.start();
    await reachedHalf.future;
    await task.pause();

    expect(task.status, DownloadStatus.paused);
    final partialLength = await File(task.filePath!).length();
    expect(partialLength, greaterThan(0));
    expect(partialLength, lessThan(content.length));

    await task.resume();
    expect(await waitForFinish(task), DownloadStatus.completed);
    expect(await File(task.filePath!).readAsBytes(), content);
  });

  test('resumes from a previous session via the repository', () async {
    final content = bytes(1000);
    final filePath = '${tempDir.path}${Platform.pathSeparator}previous.bin';
    // Simulate an earlier run that wrote the first 400 bytes.
    await File(filePath).writeAsBytes(content.sublist(0, 400));
    await repository.put(DownloadRecord(
      url: 'https://example.com/file',
      filePath: filePath,
      totalBytes: content.length,
      createdAt: DateTime.now(),
    ));

    final client = FakeDownloadClient(content);
    final manager = managerWith(client);
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );

    await task.start();
    expect(await waitForFinish(task), DownloadStatus.completed);
    expect(await File(filePath).readAsBytes(), content);
  });

  test('cancel deletes the file and the persisted record', () async {
    final manager = managerWith(FakeDownloadClient(bytes(4096), chunkSize: 8));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
      fileName: 'canceled',
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
    expect(task.progress.downloadedBytes, 0);
    expect(await File(path).exists(), isFalse);
    expect(await repository.find('https://example.com/file'), isNull);
  });

  test('fails with typed exception when the server is unreachable', () async {
    final client = FakeDownloadClient(bytes(10))..failOnOpen = true;
    final manager = managerWith(client);
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );

    await task.start();
    expect(task.status, DownloadStatus.failed);
    expect(task.progress.error, isA<ServerException>());
  });

  test('retry policy recovers from a mid-stream drop and resumes', () async {
    final content = bytes(1024);
    final client = FakeDownloadClient(content, chunkSize: 32)
      ..failAfterBytes = 256;
    final manager = managerWith(
      client,
      retryPolicy: const ExponentialBackoffRetryPolicy(
          maxRetries: 2, baseDelay: Duration(milliseconds: 1)),
    );
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
      fileName: 'flaky',
    );

    await task.start();
    expect(await waitForFinish(task), DownloadStatus.completed);
    expect(client.openCalls, 2);
    expect(await File(task.filePath!).readAsBytes(), content);
  });

  test('fails when offline and waitForConnection is disabled', () async {
    final manager = DownloadManager(
      config: DownloadConfig(
        client: FakeDownloadClient(bytes(10)),
        repository: repository,
        connectivityChecker: const _OfflineChecker(),
        retryPolicy: const NoRetryPolicy(),
      ),
    );
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );

    await task.start();
    expect(task.status, DownloadStatus.failed);
    expect(task.progress.error, isA<NoConnectionException>());
  });

  test('interceptors observe the full lifecycle', () async {
    final interceptor = RecordingInterceptor();
    final manager = managerWith(FakeDownloadClient(bytes(100)),
        interceptors: [interceptor]);
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );

    await task.start();
    await waitForFinish(task);

    expect(interceptor.events, ['create', 'start', 'complete']);
    expect(interceptor.chunkCount, greaterThan(0));
  });

  test('onCreate can rewrite the request before the task is built', () async {
    final manager = managerWith(FakeDownloadClient(bytes(10)),
        interceptors: [_RenamingInterceptor()]);
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
      fileName: 'original',
    );

    expect(task.request.fileName, 'renamed-by-interceptor');
    await task.start();
    await waitForFinish(task);
    expect(task.filePath, endsWith('renamed-by-interceptor.bin'));
  });

  test('a throwing interceptor does not break the download', () async {
    final manager = managerWith(FakeDownloadClient(bytes(100)),
        interceptors: [_ThrowingInterceptor()]);
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );

    await task.start();
    expect(await waitForFinish(task), DownloadStatus.completed);
  });

  test('using a disposed task throws DisposedTaskException', () async {
    final manager = managerWith(FakeDownloadClient(bytes(10)));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );
    await task.dispose();
    expect(task.start, throwsA(isA<DisposedTaskException>()));
  });

  Future<void> corruptByteAt(String path, int position) async {
    final raf = await File(path).open(mode: FileMode.append);
    await raf.setPosition(position);
    await raf.writeFrom([0xFF]);
    await raf.close();
  }

  Future<DownloadTask> pausedDownload(
    DownloadManager manager,
    String url, {
    int pauseAfterBytes = 512,
  }) async {
    final task = await manager.createDownload(
      url: url,
      directory: tempDir.path,
    );
    final reached = Completer<void>();
    task.progressStream.listen((p) {
      if (!reached.isCompleted && p.downloadedBytes >= pauseAfterBytes) {
        reached.complete();
      }
    });
    await task.start();
    await reached.future;
    await task.pause();
    return task;
  }

  test('detects data modified while paused and redownloads it', () async {
    final content = bytes(2048);
    final client = FakeDownloadClient(content, chunkSize: 64);
    final manager = managerWith(client);
    final task =
        await pausedDownload(manager, 'https://example.com/tampered');

    // The user opens the partial file and changes a byte in the middle.
    await corruptByteAt(task.filePath!, 100);

    await task.resume();
    expect(await waitForFinish(task), DownloadStatus.completed);
    // Verification caught the tampering and restarted from byte 0…
    expect(client.requestedRanges.last.start, 0);
    // …so the final file is byte-exact despite the corruption.
    expect(await File(task.filePath!).readAsBytes(), content);
  });

  test('detects a truncated partial file and recovers', () async {
    final content = bytes(2048);
    final client = FakeDownloadClient(content, chunkSize: 64);
    final manager = managerWith(client);
    final task =
        await pausedDownload(manager, 'https://example.com/truncated');

    // The user deletes data from the end of the partial file.
    final raf = await File(task.filePath!).open(mode: FileMode.append);
    await raf.truncate(50);
    await raf.close();

    await task.resume();
    expect(await waitForFinish(task), DownloadStatus.completed);
    expect(client.requestedRanges.last.start, 0);
    expect(await File(task.filePath!).readAsBytes(), content);
  });

  test('verifyOnResume: false skips the check (old blind-resume behavior)',
      () async {
    final content = bytes(2048);
    final client = FakeDownloadClient(content, chunkSize: 64);
    final manager = DownloadManager(
      config: DownloadConfig(
        client: client,
        repository: repository,
        connectivityChecker: const AlwaysOnlineConnectivityChecker(),
        retryPolicy: const NoRetryPolicy(),
        verifyOnResume: false,
        progressInterval: Duration.zero,
      ),
    );
    final task = await pausedDownload(manager, 'https://example.com/blind');
    await corruptByteAt(task.filePath!, 100);

    await task.resume();
    expect(await waitForFinish(task), DownloadStatus.completed);
    // Resumed blindly from the file length — the corruption survives.
    final written = await File(task.filePath!).readAsBytes();
    expect(written.length, content.length);
    expect(written[100], 0xFF);
  });

  test('restorePersistedDownloads rebuilds paused and completed tasks',
      () async {
    final content = bytes(1000);
    final pausedPath = '${tempDir.path}${Platform.pathSeparator}partial.bin';
    final donePath = '${tempDir.path}${Platform.pathSeparator}done.bin';

    // A half-finished single-stream download from a previous session…
    await File(pausedPath).writeAsBytes(content.sublist(0, 400));
    await repository.put(DownloadRecord(
      url: 'https://example.com/partial',
      filePath: pausedPath,
      totalBytes: content.length,
      createdAt: DateTime.now(),
    ));
    // …and a fully completed one.
    await File(donePath).writeAsBytes(content);
    await repository.put(DownloadRecord(
      url: 'https://example.com/done',
      filePath: donePath,
      totalBytes: content.length,
      createdAt: DateTime.now(),
    ));

    final manager = managerWith(FakeDownloadClient(content));
    final restored = await manager.restorePersistedDownloads();

    expect(restored, hasLength(2));
    final paused = restored
        .singleWhere((t) => t.request.url == 'https://example.com/partial');
    final done = restored
        .singleWhere((t) => t.request.url == 'https://example.com/done');

    // No network was touched — state came purely from storage.
    expect(paused.status, DownloadStatus.paused);
    expect(paused.progress.downloadedBytes, 400);
    expect(paused.progress.totalBytes, content.length);
    expect(paused.filePath, pausedPath);
    expect(done.status, DownloadStatus.completed);
    expect(done.progress.percent, 100);

    // The paused one can continue right away.
    await paused.start();
    expect(await waitForFinish(paused), DownloadStatus.completed);
    expect(await File(pausedPath).readAsBytes(), content);

    // Calling again must not duplicate tasks already managed.
    expect(await manager.restorePersistedDownloads(), isEmpty);
  });

  test('restoreState stays idle when nothing was persisted', () async {
    final manager = managerWith(FakeDownloadClient(bytes(10)));
    final task = await manager.createDownload(
      url: 'https://example.com/fresh',
      directory: tempDir.path,
    );
    await task.restoreState();
    expect(task.status, DownloadStatus.idle);
  });

  test('manager removes and disposes tasks', () async {
    final manager = managerWith(FakeDownloadClient(bytes(10)));
    final task = await manager.createDownload(
      url: 'https://example.com/file',
      directory: tempDir.path,
    );
    expect(manager.tasks, hasLength(1));
    expect(await manager.remove(task), isTrue);
    expect(manager.tasks, isEmpty);
    expect(task.start, throwsA(isA<DisposedTaskException>()));
  });
}

class _OfflineChecker extends ConnectivityChecker {
  const _OfflineChecker();

  @override
  Future<bool> hasConnection() async => false;
}

class _RenamingInterceptor extends DownloadInterceptor {
  @override
  Future<DownloadRequest> onCreate(DownloadRequest request) async =>
      request.copyWith(fileName: 'renamed-by-interceptor');
}

class _ThrowingInterceptor extends DownloadInterceptor {
  @override
  Future<void> onStart(DownloadTask task) async =>
      throw StateError('interceptor bug');

  @override
  void onChunk(DownloadTask task, List<int> chunk) =>
      throw StateError('interceptor bug');

  @override
  Future<void> onComplete(DownloadTask task) async =>
      throw StateError('interceptor bug');
}
