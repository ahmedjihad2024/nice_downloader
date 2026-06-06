import 'dart:developer' as developer;

import '../core/download_request.dart';
import '../engine/download_task.dart';
import 'download_interceptor.dart';

/// Logs every lifecycle event of every download via `dart:developer`.
///
/// Drop it into [DownloadConfig.interceptors] while developing:
/// ```dart
/// DownloadConfig(interceptors: [LoggingInterceptor()])
/// ```
class LoggingInterceptor extends DownloadInterceptor {
  const LoggingInterceptor({this.name = 'nice_downloader'});

  /// Logger name shown in the DevTools logging view.
  final String name;

  void _log(String message) => developer.log(message, name: name);

  @override
  Future<DownloadRequest> onCreate(DownloadRequest request) async {
    _log('create  → $request');
    return request;
  }

  @override
  Future<void> onStart(DownloadTask task) async =>
      _log('start   → ${task.request.url}');

  @override
  Future<void> onResume(DownloadTask task) async =>
      _log('resume  → ${task.request.url} from ${task.progress.readableDownloaded}');

  @override
  Future<void> onPause(DownloadTask task) async =>
      _log('pause   → ${task.request.url} at ${task.progress.percent}%');

  @override
  Future<void> onComplete(DownloadTask task) async =>
      _log('done    → ${task.request.url} (${task.progress.readableTotal}) → ${task.filePath}');

  @override
  Future<void> onCancel(DownloadTask task) async =>
      _log('cancel  → ${task.request.url}');

  @override
  Future<void> onError(
          DownloadTask task, Object error, StackTrace stackTrace) async =>
      _log('error   → ${task.request.url}: $error');
}
