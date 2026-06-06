import 'dart:async';

import '../core/download_request.dart';
import '../core/exceptions.dart';
import '../io/file_writer.dart';
import '../network/download_client.dart';
import '../network/retry_policy.dart';
import '../utils/crc32.dart';
import 'bandwidth_throttle.dart';
import 'segment.dart';

/// Downloads one byte range of a segmented download over its own connection,
/// writing directly at the segment's offset in the pre-allocated file.
///
/// Each segment retries independently: a dropped connection resumes from
/// `segment.nextByte` without disturbing the other segments. Internal to the
/// engine — not exported.
class SegmentDownloader {
  SegmentDownloader({
    required this.segment,
    required DownloadRequest request,
    required String filePath,
    required DownloadClient client,
    required DownloadFileWriter writer,
    required RetryPolicy retryPolicy,
    required BandwidthThrottle throttle,
    required void Function(List<int> chunk) onChunk,
    this.trackIntegrity = true,
  })  : _request = request,
        _filePath = filePath,
        _client = client,
        _writer = writer,
        _retryPolicy = retryPolicy,
        _throttle = throttle,
        _onChunk = onChunk;

  /// The range this downloader is responsible for (shared, mutable state —
  /// the task reads aggregate progress from it).
  final Segment segment;

  /// When `true`, a running CRC-32 of the written bytes is kept on the
  /// segment so the data can be verified before a later resume.
  final bool trackIntegrity;

  final DownloadRequest _request;
  final String _filePath;
  final DownloadClient _client;
  final DownloadFileWriter _writer;
  final RetryPolicy _retryPolicy;

  /// Shared with the task and its other segments, so the limit caps the
  /// download's total speed — not each connection separately.
  final BandwidthThrottle _throttle;
  final void Function(List<int> chunk) _onChunk;

  DownloadConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _streamDone;
  Completer<void>? _sleeper;
  Future<void>? _runFuture;
  bool _stopped = false;

  /// Downloads the segment to completion, retrying per the policy.
  /// Returns normally when complete or stopped; throws when the policy
  /// gives up.
  Future<void> run() => _runFuture ??= _run();

  /// Stops the transfer and waits until [run] has fully released its
  /// resources (connection, file handle) — crucial on Windows, where an open
  /// handle blocks file deletion. Idempotent.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final done = _streamDone;
    if (done != null && !done.isCompleted) done.complete();
    final sleeper = _sleeper;
    if (sleeper != null && !sleeper.isCompleted) sleeper.complete();
    await _release();

    final runFuture = _runFuture;
    if (runFuture != null) {
      try {
        await runFuture;
      } catch (_) {
        // run()'s error is surfaced through the task's supervisor.
      }
    }
  }

  Future<void> _run() async {
    var attempt = 0;
    while (!_stopped && !segment.isComplete) {
      final downloadedBefore = segment.downloaded;
      try {
        final connection = await _client.open(
          _request.copyWith(rangeEnd: segment.end),
          startByte: segment.nextByte,
        );
        if (_stopped) {
          await connection.close();
          return;
        }
        if (segment.nextByte > 0 && !connection.supportsResume) {
          await connection.close();
          throw const RangeNotSupportedException();
        }
        _connection = connection;
        await _writer.openAt(_filePath, segment.nextByte);
        if (_stopped) {
          await _release();
          return;
        }

        await _consume(connection);
        await _release();
        if (_stopped) return;
        if (!segment.isComplete) {
          // Stream ended early — let the retry policy decide.
          throw const ConnectionLostException();
        }
      } catch (error) {
        await _release();
        if (_stopped) return;
        if (segment.downloaded > downloadedBefore) attempt = 0;
        attempt++;
        final delay = _retryPolicy.delayBeforeRetry(attempt, error);
        if (delay == null) rethrow;
        await _interruptibleDelay(delay);
      }
    }
  }

  Future<void> _consume(DownloadConnection connection) {
    final done = _streamDone = Completer<void>();
    _subscription = connection.byteStream.listen(
      (chunk) {
        if (_stopped || segment.isComplete) return;
        var data = chunk;
        // Clamp: a non-compliant server may send more than the range.
        final remaining = segment.length - segment.downloaded;
        if (data.length > remaining) data = data.sublist(0, remaining);
        _writer.write(data);
        segment.downloaded += data.length;
        if (trackIntegrity) segment.crc = crc32Update(segment.crc, data);
        _onChunk(data);
        if (segment.isComplete && !done.isCompleted) done.complete();
        final delay = _throttle.consume(data.length);
        if (delay != null) _subscription?.pause(Future<void>.delayed(delay));
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!done.isCompleted) done.completeError(error, stackTrace);
      },
      cancelOnError: true,
    );
    return done.future;
  }

  /// A delay that [stop] can cut short, so pause/cancel never waits out a
  /// retry backoff.
  Future<void> _interruptibleDelay(Duration delay) {
    final sleeper = _sleeper = Completer<void>();
    Timer(delay, () {
      if (!sleeper.isCompleted) sleeper.complete();
    });
    return sleeper.future;
  }

  Future<void> _release() async {
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    await _writer.close();
  }
}
