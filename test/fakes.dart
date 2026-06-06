import 'dart:async';

import 'package:nice_downloader/nice_downloader.dart';

/// Serves [content] from memory, honoring range requests like a real server.
class FakeDownloadClient extends DownloadClient {
  FakeDownloadClient(
    this.content, {
    this.chunkSize = 16,
    this.supportsResume = true,
    this.failAfterBytes,
    this.failOnOpen = false,
    this.maxConcurrentConnections,
    this.chunkDelay = Duration.zero,
    this.suggestedFileName = 'fake_file',
    this.fileExtension = 'bin',
  });

  final List<int> content;
  final int chunkSize;
  final bool supportsResume;

  /// When set, connections beyond this limit are rejected with HTTP 429 —
  /// simulates a per-IP rate-limiting server (like Hetzner's).
  final int? maxConcurrentConnections;

  /// Pause between chunks, to keep connections open long enough for
  /// concurrency tests.
  final Duration chunkDelay;

  final String? suggestedFileName;
  final String? fileExtension;

  /// When set, the stream errors after delivering this many bytes.
  int? failAfterBytes;

  /// When `true`, [open] throws (simulates an unreachable server).
  bool failOnOpen;

  int openCalls = 0;
  int activeConnections = 0;
  int rejectedWith429 = 0;

  /// Every requested range, for asserting segmentation behavior.
  final List<({int start, int? end})> requestedRanges = [];

  @override
  Future<DownloadConnection> open(DownloadRequest request,
      {required int startByte}) async {
    openCalls++;
    requestedRanges.add((start: startByte, end: request.rangeEnd));
    if (failOnOpen) throw const ServerException(503);

    final limit = maxConcurrentConnections;
    if (limit != null && activeConnections >= limit) {
      rejectedWith429++;
      throw const ServerException(429,
          retryAfter: Duration(milliseconds: 20));
    }

    // A compliant server honors the range and answers 206; a non-compliant
    // one ignores it and streams the whole file from byte 0.
    final start = supportsResume ? startByte : 0;
    final rangeEnd = request.rangeEnd;
    final endExclusive = supportsResume && rangeEnd != null
        ? (rangeEnd + 1 < content.length ? rangeEnd + 1 : content.length)
        : content.length;
    final remaining = content.sublist(start, endExclusive);

    activeConnections++;
    var closed = false;
    Future<void> release() async {
      if (!closed) {
        closed = true;
        activeConnections--;
      }
    }

    return DownloadConnection(
      byteStream: _streamOf(remaining, release),
      contentLength: remaining.length,
      supportsResume: supportsResume,
      suggestedFileName: suggestedFileName,
      fileExtension: fileExtension,
      onClose: release,
    );
  }

  Stream<List<int>> _streamOf(
      List<int> bytes, Future<void> Function() release) async* {
    try {
      var delivered = 0;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final chunk = bytes.sublist(
            i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
        yield chunk;
        delivered += chunk.length;
        final failAt = failAfterBytes;
        if (failAt != null && delivered >= failAt) {
          failAfterBytes = null; // fail only once, recover on retry
          throw const ServerException(500, cause: 'connection dropped');
        }
        // Let the event loop breathe so pause/cancel can interleave.
        await Future<void>.delayed(chunkDelay);
      }
    } finally {
      await release();
    }
  }
}

/// Records every lifecycle callback it receives.
class RecordingInterceptor extends DownloadInterceptor {
  final List<String> events = [];
  int chunkCount = 0;

  @override
  Future<DownloadRequest> onCreate(DownloadRequest request) async {
    events.add('create');
    return request;
  }

  @override
  Future<void> onStart(DownloadTask task) async => events.add('start');

  @override
  Future<void> onResume(DownloadTask task) async => events.add('resume');

  @override
  void onChunk(DownloadTask task, List<int> chunk) => chunkCount++;

  @override
  Future<void> onPause(DownloadTask task) async => events.add('pause');

  @override
  Future<void> onComplete(DownloadTask task) async => events.add('complete');

  @override
  Future<void> onCancel(DownloadTask task) async => events.add('cancel');

  @override
  Future<void> onError(
          DownloadTask task, Object error, StackTrace stackTrace) async =>
      events.add('error');
}
