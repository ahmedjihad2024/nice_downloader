/// Base type for every error thrown by this package.
///
/// Catch this to handle any downloader failure in one place:
/// ```dart
/// try {
///   await task.start();
/// } on NiceDownloaderException catch (e) {
///   // ...
/// }
/// ```
abstract class NiceDownloaderException implements Exception {
  const NiceDownloaderException(this.message, {this.cause});

  /// Human readable description of what went wrong.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// There is no internet connection and `waitForConnection` is disabled.
class NoConnectionException extends NiceDownloaderException {
  const NoConnectionException()
      : super('No internet connection available.');
}

/// The server answered with a non-success status code.
class ServerException extends NiceDownloaderException {
  const ServerException(this.statusCode, {this.retryAfter, Object? cause})
      : super('Server responded with status code $statusCode.', cause: cause);

  /// The HTTP status code returned by the server.
  final int statusCode;

  /// How long the server asked us to back off (`Retry-After` header),
  /// typically sent with 429/503. Honored by [ExponentialBackoffRetryPolicy].
  final Duration? retryAfter;
}

/// A download task was used after [DownloadTask.dispose] was called.
class DisposedTaskException extends NiceDownloaderException {
  const DisposedTaskException()
      : super('This DownloadTask has been disposed and can no longer be used.');
}

/// Reading or writing persisted download state failed.
class StorageException extends NiceDownloaderException {
  const StorageException(super.message, {super.cause});
}

/// The server stopped honoring range requests while a segmented download was
/// in progress, so the remaining segments cannot be fetched at their offsets.
class RangeNotSupportedException extends NiceDownloaderException {
  const RangeNotSupportedException()
      : super('Server does not honor range requests; '
            'cannot continue a segmented download.');
}

/// The connection closed before all expected bytes were received.
class ConnectionLostException extends NiceDownloaderException {
  const ConnectionLostException()
      : super('Connection closed before all bytes were received.');
}
