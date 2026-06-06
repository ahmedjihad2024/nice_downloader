import 'package:path/path.dart' as p;

import '../core/download_request.dart';
import '../engine/download_task.dart';
import '../interceptors/download_interceptor.dart';
import '../storage/download_record.dart';
import '../storage/download_repository.dart';
import '../storage/hive_download_repository.dart';
import 'download_config.dart';

/// Facade and single entry point of the package: creates [DownloadTask]s
/// wired with the collaborators from [DownloadConfig] and offers bulk
/// operations over them.
///
/// ```dart
/// final manager = DownloadManager();
/// final task = await manager.createDownload(
///   url: 'https://example.com/video.mp4',
///   directory: downloadsDir.path,
/// );
/// task.progressStream.listen(print);
/// await task.start();
/// ```
class DownloadManager {
  DownloadManager({DownloadConfig config = const DownloadConfig()})
      : _config = config,
        _repository = config.repository ?? HiveDownloadRepository(),
        _interceptors = InterceptorChain(config.interceptors);

  final DownloadConfig _config;
  final DownloadRepository _repository;
  final InterceptorChain _interceptors;
  final List<DownloadTask> _tasks = [];

  /// The tasks created by this manager (read-only view).
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// Creates a new [DownloadTask].
  ///
  /// The request first flows through every interceptor's
  /// [DownloadInterceptor.onCreate], which may rewrite it. The task is *not*
  /// started automatically — call [DownloadTask.start] when ready (or pass
  /// [startImmediately]).
  Future<DownloadTask> createDownload({
    required String url,
    required String directory,
    String? fileName,
    Map<String, String> headers = const {},
    int? speedLimit,
    bool startImmediately = false,
  }) async {
    final request = await _interceptors.proceedCreate(DownloadRequest(
      url: url,
      directory: directory,
      fileName: fileName,
      headers: headers,
    ));

    final task = DownloadTask(
      request: request,
      client: _config.client,
      repository: _repository,
      connectivityChecker: _config.connectivityChecker,
      retryPolicy: _config.retryPolicy,
      interceptors: _interceptors,
      segmentPlanner: _config.segmentPlanner,
      fileWriterFactory: _config.fileWriterFactory,
      speedLimit: speedLimit ?? _config.speedLimit,
      verifyOnResume: _config.verifyOnResume,
      connectionStagger: _config.connectionStagger,
      waitForConnection: _config.waitForConnection,
      progressInterval: _config.progressInterval,
    );
    _tasks.add(task);

    if (startImmediately) await task.start();
    return task;
  }

  /// Downloads persisted in earlier sessions — use this to rebuild a
  /// downloads screen after an app restart.
  Future<List<DownloadRecord>> persistedDownloads() => _repository.findAll();

  /// Recreates one task per persisted download and restores its progress
  /// from storage — completed downloads show as completed, partial ones as
  /// paused (resume with [DownloadTask.start]). Nothing is started and the
  /// network is not touched. URLs already managed by this instance are
  /// skipped.
  ///
  /// ```dart
  /// // On app start:
  /// final tasks = await manager.restorePersistedDownloads();
  /// ```
  Future<List<DownloadTask>> restorePersistedDownloads() async {
    final records = await _repository.findAll();
    final restored = <DownloadTask>[];
    for (final record in records) {
      if (_tasks.any((task) => task.request.url == record.url)) continue;
      final task = await createDownload(
        url: record.url,
        directory: p.dirname(record.filePath),
      );
      await task.restoreState();
      restored.add(task);
    }
    return restored;
  }

  /// Starts (or resumes) every task.
  Future<void> startAll() =>
      Future.wait(_tasks.map((task) => task.start()));

  /// Pauses every active task.
  Future<void> pauseAll() =>
      Future.wait(_tasks.map((task) => task.pause()));

  /// Cancels every task.
  Future<void> cancelAll({bool deleteFiles = true}) =>
      Future.wait(_tasks.map((task) => task.cancel(deleteFile: deleteFiles)));

  /// Removes [task] from this manager and disposes it.
  Future<bool> remove(DownloadTask task) async {
    final removed = _tasks.remove(task);
    if (removed) await task.dispose();
    return removed;
  }

  /// Disposes every task and clears the manager.
  Future<void> dispose() async {
    await Future.wait(_tasks.map((task) => task.dispose()));
    _tasks.clear();
  }
}
