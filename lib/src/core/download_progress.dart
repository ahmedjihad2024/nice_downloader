import 'package:meta/meta.dart';

import '../utils/byte_format.dart';
import 'download_status.dart';

/// An immutable snapshot of a download at a point in time.
///
/// Emitted on [DownloadTask.progressStream]; every event is a *new* instance,
/// so it is safe to keep references to old snapshots (e.g. for diffing).
@immutable
class DownloadProgress {
  const DownloadProgress({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.bytesPerSecond,
    this.error,
  });

  /// The state of a task that has not been started yet.
  const DownloadProgress.initial()
      : this(
          status: DownloadStatus.idle,
          downloadedBytes: 0,
          totalBytes: 0,
        );

  /// Current lifecycle state.
  final DownloadStatus status;

  /// Bytes written to disk so far.
  final int downloadedBytes;

  /// Expected total size in bytes. `0` while still unknown.
  final int totalBytes;

  /// Current transfer speed. `null` when not actively downloading.
  final double? bytesPerSecond;

  /// The error that moved the task to [DownloadStatus.failed], if any.
  final Object? error;

  /// Completion percentage in the range `0.0 .. 100.0`.
  double get percent {
    if (totalBytes <= 0) return 0;
    return double.parse(
      (downloadedBytes * 100 / totalBytes).clamp(0, 100).toStringAsFixed(2),
    );
  }

  /// [downloadedBytes] in a readable unit, e.g. `12.5 MB`.
  ByteFormat get readableDownloaded => downloadedBytes.readableSize;

  /// [totalBytes] in a readable unit.
  ByteFormat get readableTotal => totalBytes.readableSize;

  /// [bytesPerSecond] in a readable unit, e.g. `1.2 MB/s`.
  ByteFormat? get readableSpeed => bytesPerSecond?.readableSpeed;

  static const Object _unset = Object();

  /// Returns a new snapshot with the given fields replaced.
  ///
  /// [bytesPerSecond] and [error] use a sentinel default so they can be
  /// explicitly cleared by passing `null`.
  DownloadProgress copyWith({
    DownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    Object? bytesPerSecond = _unset,
    Object? error = _unset,
  }) {
    return DownloadProgress(
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: identical(bytesPerSecond, _unset)
          ? this.bytesPerSecond
          : bytesPerSecond as double?,
      error: identical(error, _unset) ? this.error : error,
    );
  }

  @override
  String toString() =>
      'DownloadProgress(status: ${status.name}, $readableDownloaded / '
      '$readableTotal, $percent%'
      '${readableSpeed != null ? ', $readableSpeed' : ''})';
}
