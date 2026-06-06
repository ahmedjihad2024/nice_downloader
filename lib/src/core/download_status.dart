/// The lifecycle state of a download.
enum DownloadStatus {
  /// Created but never started.
  idle,

  /// Resolving connectivity / opening the HTTP connection.
  connecting,

  /// Bytes are actively being written to disk.
  downloading,

  /// Stopped by the user; can be resumed from the current byte offset.
  paused,

  /// All bytes written successfully.
  completed,

  /// Stopped by an unrecoverable error (after the retry policy gave up).
  failed,

  /// Canceled by the user; partial file and persisted state were removed.
  canceled;

  /// Whether the task is doing work right now.
  bool get isActive => this == connecting || this == downloading;

  /// Whether the task reached a terminal state.
  bool get isFinished =>
      this == completed || this == failed || this == canceled;

  /// Whether the task can be (re)started from its current state.
  bool get canStart => !isActive && this != completed;
}
