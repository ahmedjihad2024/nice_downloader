import '../core/download_request.dart';
import '../engine/download_task.dart';

/// Hook into every step of a download's lifecycle without modifying the
/// engine (Open/Closed principle) — the same idea as Dio's interceptors.
///
/// Register interceptors via [DownloadConfig.interceptors]; they are invoked
/// in registration order. Typical uses: logging, analytics, notifications,
/// rewriting requests (auth headers, renaming files), checksum validation
/// in [onComplete], …
///
/// ```dart
/// class AuthInterceptor extends DownloadInterceptor {
///   @override
///   Future<DownloadRequest> onCreate(DownloadRequest request) async =>
///       request.copyWith(headers: {...request.headers, 'Authorization': 'Bearer …'});
/// }
/// ```
///
/// All methods have no-op defaults — override only what you need.
abstract class DownloadInterceptor {
  const DownloadInterceptor();

  /// Called before a task is created. Return a (possibly modified) request;
  /// this is the only hook that can change *what* gets downloaded.
  Future<DownloadRequest> onCreate(DownloadRequest request) async => request;

  /// Called when [DownloadTask.start] begins a fresh download.
  Future<void> onStart(DownloadTask task) async {}

  /// Called when a paused/interrupted download continues from a byte offset.
  Future<void> onResume(DownloadTask task) async {}

  /// Called for every received chunk. Keep this *fast and synchronous* — it
  /// runs on the hot path of the byte stream. Note: in segmented downloads
  /// chunks from different connections arrive interleaved.
  void onChunk(DownloadTask task, List<int> chunk) {}

  /// Called after the user paused the download.
  Future<void> onPause(DownloadTask task) async {}

  /// Called once all bytes were written successfully.
  Future<void> onComplete(DownloadTask task) async {}

  /// Called after the user canceled the download.
  Future<void> onCancel(DownloadTask task) async {}

  /// Called when the download failed (after the retry policy gave up).
  Future<void> onError(
      DownloadTask task, Object error, StackTrace stackTrace) async {}
}

/// Runs a list of interceptors in order (Chain of Responsibility).
///
/// Lifecycle notifications are isolated: an interceptor that throws cannot
/// break the download or starve later interceptors. [onCreate] is the
/// exception — it transforms the request, so its errors propagate.
class InterceptorChain {
  const InterceptorChain(this._interceptors);

  final List<DownloadInterceptor> _interceptors;

  Future<DownloadRequest> proceedCreate(DownloadRequest request) async {
    var current = request;
    for (final interceptor in _interceptors) {
      current = await interceptor.onCreate(current);
    }
    return current;
  }

  Future<void> notifyStart(DownloadTask task) =>
      _notify((i) => i.onStart(task));

  Future<void> notifyResume(DownloadTask task) =>
      _notify((i) => i.onResume(task));

  void notifyChunk(DownloadTask task, List<int> chunk) {
    for (final interceptor in _interceptors) {
      try {
        interceptor.onChunk(task, chunk);
      } catch (_) {
        // A misbehaving interceptor must not abort the transfer.
      }
    }
  }

  Future<void> notifyPause(DownloadTask task) =>
      _notify((i) => i.onPause(task));

  Future<void> notifyComplete(DownloadTask task) =>
      _notify((i) => i.onComplete(task));

  Future<void> notifyCancel(DownloadTask task) =>
      _notify((i) => i.onCancel(task));

  Future<void> notifyError(
          DownloadTask task, Object error, StackTrace stackTrace) =>
      _notify((i) => i.onError(task, error, stackTrace));

  Future<void> _notify(
      Future<void> Function(DownloadInterceptor interceptor) call) async {
    for (final interceptor in _interceptors) {
      try {
        await call(interceptor);
      } catch (_) {
        // A misbehaving interceptor must not break the download lifecycle.
      }
    }
  }
}
