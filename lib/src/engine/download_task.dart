import 'dart:async';

import 'package:path/path.dart' as p;

import '../core/download_progress.dart';
import '../core/download_request.dart';
import '../core/download_status.dart';
import '../core/exceptions.dart';
import '../interceptors/download_interceptor.dart';
import '../io/file_writer.dart';
import '../network/connectivity_checker.dart';
import '../network/download_client.dart';
import '../network/retry_policy.dart';
import '../storage/download_record.dart';
import '../storage/download_repository.dart';
import '../utils/crc32.dart';
import 'bandwidth_throttle.dart';
import 'segment.dart';
import 'segment_downloader.dart';
import 'segment_planner.dart';
import 'speed_tracker.dart';

/// A single download with pause / resume / cancel support.
///
/// Tasks are created via [DownloadManager.createDownload]; all collaborators
/// (client, repository, writer, …) are injected, so each piece can be swapped
/// or faked independently.
///
/// When the server supports range requests and the file is large enough, the
/// download is automatically split into parallel segments (IDM-style
/// multi-connection downloading) according to the configured
/// [SegmentPlanner]. Otherwise it transparently falls back to a single
/// stream — same API, same progress events.
///
/// State machine:
/// ```
/// idle ──start──▶ connecting ──▶ downloading ──▶ completed
///                     │               │
///                     │             pause ──▶ paused ──resume──▶ connecting
///                     │               │
///                     └── failed ◀────┴──▶ canceled
/// ```
/// Calls that are invalid in the current state (e.g. `pause()` while idle,
/// `start()` while downloading) are no-ops — never crashes.
class DownloadTask {
  DownloadTask({
    required DownloadRequest request,
    required DownloadClient client,
    required DownloadRepository repository,
    required ConnectivityChecker connectivityChecker,
    required RetryPolicy retryPolicy,
    required InterceptorChain interceptors,
    required SegmentPlanner segmentPlanner,
    required DownloadFileWriter Function() fileWriterFactory,
    int? speedLimit,
    this.waitForConnection = false,
    this.verifyOnResume = true,
    this.progressInterval = const Duration(milliseconds: 100),
    this.connectionStagger = const Duration(milliseconds: 200),
  })  : _throttle = BandwidthThrottle(bytesPerSecond: speedLimit),
        _request = request,
        _client = client,
        _repository = repository,
        _connectivity = connectivityChecker,
        _retryPolicy = retryPolicy,
        _interceptors = interceptors,
        _segmentPlanner = segmentPlanner,
        _writerFactory = fileWriterFactory,
        _writer = fileWriterFactory();

  /// How often the per-segment state of a segmented download is persisted —
  /// bounds how many bytes are re-downloaded after a crash.
  static const Duration _statePersistInterval = Duration(seconds: 1);

  /// Delay between opening consecutive segment connections. Bursting all
  /// connections in the same instant trips rate limiters (HTTP 429) on many
  /// servers; a small ramp keeps them happy at negligible cost.
  final Duration connectionStagger;

  /// Cooldown before retrying with fewer connections after a 429 whose
  /// response carried no `Retry-After` header.
  static const Duration _rateLimitCooldown = Duration(seconds: 10);

  /// When `true`, [start] blocks until connectivity returns instead of
  /// failing immediately while offline.
  final bool waitForConnection;

  /// When `true` (the default), a CRC-32 of every written byte is persisted
  /// alongside the progress, and on resume the on-disk data is re-checked
  /// against it. Data that was modified, truncated or deleted while the
  /// download was paused is detected and only the damaged part is fetched
  /// again (per segment for segmented downloads). Client-side — works with
  /// any server.
  final bool verifyOnResume;

  /// Minimum time between two progress events while downloading (status
  /// changes are always emitted immediately).
  final Duration progressInterval;

  final DownloadRequest _request;
  final DownloadClient _client;
  final DownloadRepository _repository;
  final ConnectivityChecker _connectivity;
  final RetryPolicy _retryPolicy;
  final InterceptorChain _interceptors;
  final SegmentPlanner _segmentPlanner;
  final DownloadFileWriter Function() _writerFactory;
  final DownloadFileWriter _writer;

  final StreamController<DownloadProgress> _controller =
      StreamController<DownloadProgress>.broadcast();
  final Stopwatch _emitWatch = Stopwatch();
  final Stopwatch _persistWatch = Stopwatch();
  final SpeedTracker _speed = SpeedTracker();
  final BandwidthThrottle _throttle;

  DownloadProgress _progress = const DownloadProgress.initial();
  DownloadConnection? _connection;
  StreamSubscription<List<int>>? _subscription;
  List<Segment>? _segments;
  List<SegmentDownloader>? _segmentDownloaders;
  String? _filePath;
  DateTime? _createdAt;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  int _streamCrc = 0;
  int _retryAttempt = 0;
  int? _concurrencyCap; // learned from 429s; sticks for the task's lifetime
  bool _disposed = false;

  /// What this task downloads and where it stores it.
  DownloadRequest get request => _request;

  /// Absolute path of the local file; `null` until the download started once.
  String? get filePath => _filePath;

  /// The latest progress snapshot (also available to late subscribers).
  DownloadProgress get progress => _progress;

  /// Current lifecycle state — shorthand for `progress.status`.
  DownloadStatus get status => _progress.status;

  /// Broadcast stream of progress snapshots. Subscribe before calling
  /// [start] to observe every state transition.
  Stream<DownloadProgress> get progressStream => _controller.stream;

  /// Total transfer speed cap in bytes/second, applied across all parallel
  /// segments together. `null` (the default) means unlimited — max speed.
  ///
  /// Can be changed while the download is running.
  int? get speedLimit => _throttle.bytesPerSecond;

  set speedLimit(int? bytesPerSecond) =>
      _throttle.bytesPerSecond = bytesPerSecond;

  /// Starts — or resumes — the download.
  ///
  /// Existing partial data (from this session or a previous app run) is
  /// detected through the repository and the download continues from the
  /// last written bytes when the server supports range requests — per
  /// segment for segmented downloads.
  Future<void> start() async {
    _ensureNotDisposed();
    if (!status.canStart) return;

    final resuming = _downloadedBytes > 0 || status == DownloadStatus.paused;
    _emit(_progress.copyWith(status: DownloadStatus.connecting));
    if (resuming) {
      await _interceptors.notifyResume(this);
    } else {
      await _interceptors.notifyStart(this);
    }

    try {
      await _run();
    } catch (error, stackTrace) {
      await _fail(error, stackTrace);
    }
  }

  /// Alias for [start]; reads naturally after a [pause].
  Future<void> resume() => start();

  /// Loads persisted progress (file path, bytes, segments) from the
  /// repository *without* touching the network, so a UI can show resumable
  /// and completed downloads right after an app restart.
  ///
  /// Emits [DownloadStatus.completed] when all bytes are already on disk,
  /// [DownloadStatus.paused] when partial data exists, and stays
  /// [DownloadStatus.idle] when nothing was persisted. Only valid before the
  /// task is started.
  Future<void> restoreState() async {
    _ensureNotDisposed();
    if (status != DownloadStatus.idle) return;

    final restored = await _restorePersistedState();
    final segments = restored.segments;
    _downloadedBytes = segments != null
        ? segments.fold(0, (sum, s) => sum + s.downloaded)
        : restored.offset;
    if (_filePath == null) return; // nothing persisted — stay idle

    final complete = _totalBytes > 0 && _downloadedBytes >= _totalBytes;
    _emit(_progress.copyWith(
      status: complete ? DownloadStatus.completed : DownloadStatus.paused,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
    ));
  }

  /// Pauses the download, keeping the partial file and persisted state so a
  /// later [resume] continues from the current offset(s).
  Future<void> pause() async {
    _ensureNotDisposed();
    if (!status.isActive) return;

    await _closeIO();
    _emit(_progress.copyWith(
        status: DownloadStatus.paused, bytesPerSecond: null));
    await _interceptors.notifyPause(this);
  }

  /// Cancels the download, removing the persisted state and — unless
  /// [deleteFile] is `false` — the partial file.
  Future<void> cancel({bool deleteFile = true}) async {
    _ensureNotDisposed();
    if (status == DownloadStatus.canceled) return;

    await _closeIO();
    final path = _filePath;
    if (deleteFile && path != null) {
      try {
        await _writer.delete(path);
      } catch (_) {
        // The partial file may be locked or already gone; the cancel itself
        // must still succeed.
      }
    }
    await _repository.delete(_request.url);

    _segments = null;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _streamCrc = 0;
    _emit(_progress.copyWith(
      status: DownloadStatus.canceled,
      downloadedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: null,
    ));
    await _interceptors.notifyCancel(this);
  }

  /// Releases all resources. The task must not be used afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _closeIO();
    await _controller.close();
  }

  // ─────────────────────────── internals ───────────────────────────

  Future<void> _run() async {
    if (!await _connectivity.hasConnection()) {
      if (!waitForConnection) throw const NoConnectionException();
      await _connectivity.waitForConnection();
    }

    final restored = await _restorePersistedState(verify: verifyOnResume);

    // A segmented download from a previous session — resume each segment.
    final restoredSegments = restored.segments;
    if (restoredSegments != null) {
      _downloadedBytes =
          restoredSegments.fold(0, (sum, s) => sum + s.downloaded);
      if (restoredSegments.every((s) => s.isComplete)) {
        await _complete();
        return;
      }
      await _startSegmented(restoredSegments);
      return;
    }

    var offset = restored.offset;
    if (_totalBytes > 0 && offset >= _totalBytes) {
      _downloadedBytes = offset;
      await _complete();
      return;
    }

    final connection = await _openWithRetry(offset);
    if (_disposed || !status.isActive) {
      // Canceled or paused while the connection was being opened.
      await connection.close();
      return;
    }

    if (offset > 0 && !connection.supportsResume) {
      // Server ignored the Range header — restart from scratch.
      final path = _filePath;
      if (path != null) await _writer.delete(path);
      offset = 0;
      _streamCrc = 0;
    }

    _filePath ??= _resolveFilePath(connection);
    _totalBytes = offset + connection.contentLength;

    // Segmentation decision: range support confirmed, size known, and the
    // planner wants more than one part → go multi-connection.
    if (_request.rangeEnd == null &&
        connection.supportsResume &&
        connection.contentLength > 0) {
      final planned =
          _segmentPlanner.plan(start: offset, endExclusive: _totalBytes);
      if (planned.length > 1) {
        await connection.close(); // the probe did its job
        final segments = [
          // Bytes downloaded single-stream before segmentation kicked in.
          if (offset > 0) Segment(start: 0, end: offset - 1, downloaded: offset),
          ...planned,
        ];
        _downloadedBytes = offset;
        await _writer.allocate(_filePath!, _totalBytes);
        await _startSegmented(segments);
        return;
      }
    }

    // Single-stream path (small file, no range support, or custom range).
    _connection = connection;
    _downloadedBytes = offset;
    await _persistSingleStream();

    // Write at the verified offset (the file may contain an unverified tail
    // beyond it, which gets overwritten), or truncate for a fresh start.
    if (offset > 0) {
      await _writer.openAt(_filePath!, offset);
    } else {
      await _writer.open(_filePath!, append: false);
    }

    _emit(_progress.copyWith(
      status: DownloadStatus.downloading,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
    ));
    _speed.start();
    _emitWatch
      ..reset()
      ..start();
    _persistWatch
      ..reset()
      ..start();

    _subscription = connection.byteStream.listen(
      _onChunk,
      onDone: _onDone,
      onError: _onStreamError,
      cancelOnError: true,
    );
  }

  // ───────────────────────── segmented path ─────────────────────────

  /// Spawns one [SegmentDownloader] per incomplete segment; they share the
  /// pre-allocated file, each writing at its own offset.
  Future<void> _startSegmented(List<Segment> segments) async {
    _segments = segments;
    _downloadedBytes = segments.fold(0, (sum, s) => sum + s.downloaded);
    await _persistSegments(); // crash-safe before any byte is written

    _emit(_progress.copyWith(
      status: DownloadStatus.downloading,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
    ));
    _speed.start();
    _emitWatch
      ..reset()
      ..start();
    _persistWatch
      ..reset()
      ..start();

    unawaited(_superviseSegments(segments));
  }

  /// Runs segment downloads in rounds. On HTTP 429 ("Too Many Requests") the
  /// number of parallel connections is halved and the round retried after a
  /// cooldown — IDM-style adaptation to per-IP connection limits — until a
  /// single connection also fails.
  Future<void> _superviseSegments(List<Segment> segments) async {
    while (true) {
      final pending =
          [for (final s in segments) if (!s.isComplete) s];
      if (pending.isEmpty) break;

      final downloaders = [for (final s in pending) _newDownloader(s)];
      _segmentDownloaders = downloaders;
      final cap = _concurrencyCap == null ||
              _concurrencyCap! >= downloaders.length
          ? downloaders.length
          : _concurrencyCap!;

      try {
        await _runPool(downloaders, cap);
      } catch (error, stackTrace) {
        for (final downloader in downloaders) {
          await downloader.stop();
        }
        _segmentDownloaders = null;
        if (_disposed || !status.isActive) return;
        await _persistSegments();

        if (error is ServerException && error.statusCode == 429 && cap > 1) {
          // The server limits connections per IP — halve and try again.
          _concurrencyCap = cap > 2 ? cap ~/ 2 : 1;
          await Future<void>.delayed(error.retryAfter ?? _rateLimitCooldown);
          if (_disposed || !status.isActive) return;
          continue;
        }
        await _fail(error, stackTrace);
        return;
      }
      _segmentDownloaders = null;
      break;
    }

    if (_disposed || !status.isActive) return;
    // Stopped via pause/cancel — runs return normally without completing.
    final complete = _segments?.every((s) => s.isComplete) ?? false;
    if (!complete) return;

    await _persistSegments();
    await _complete();
  }

  /// Runs the downloaders with at most [cap] active at once, ramping the
  /// workers up with [connectionStagger] between starts.
  Future<void> _runPool(List<SegmentDownloader> downloaders, int cap) async {
    var next = 0;
    Future<void> worker(int index) async {
      if (index > 0) {
        await Future<void>.delayed(connectionStagger * index);
      }
      while (!_disposed && status.isActive) {
        final i = next++;
        if (i >= downloaders.length) return;
        await downloaders[i].run();
      }
    }

    await Future.wait(
      [for (var w = 0; w < cap; w++) worker(w)],
      eagerError: true,
    );
  }

  SegmentDownloader _newDownloader(Segment segment) => SegmentDownloader(
        segment: segment,
        request: _request,
        filePath: _filePath!,
        client: _client,
        writer: _writerFactory(),
        retryPolicy: _retryPolicy,
        throttle: _throttle, // shared — caps the TOTAL speed
        trackIntegrity: verifyOnResume,
        onChunk: _onSegmentChunk,
      );

  void _onSegmentChunk(List<int> chunk) {
    _recordProgress(chunk);
    if (_persistWatch.elapsed >= _statePersistInterval) {
      _persistWatch
        ..reset()
        ..start();
      unawaited(_persistSegments());
    }
  }

  Future<void> _persistSegments() async {
    final segments = _segments;
    final path = _filePath;
    if (segments == null || path == null) return;
    _createdAt ??= DateTime.now();
    await _repository.put(DownloadRecord(
      url: _request.url,
      filePath: path,
      totalBytes: _totalBytes,
      createdAt: _createdAt!,
      segments: [for (final segment in segments) segment.toProgress()],
    ));
  }

  // ──────────────────────── shared internals ────────────────────────

  /// Restores state from a previous session, dropping stale records whose
  /// file vanished. Returns the single-stream byte offset, or the segment
  /// list for segmented downloads.
  ///
  /// With [verify], the on-disk bytes are checked against their persisted
  /// CRC-32 first: damaged single-stream data restarts from zero, damaged
  /// segments are reset individually so only the broken ranges are fetched
  /// again. Without [verify] (e.g. [restoreState] for UI display) no file
  /// content is read.
  Future<({int offset, List<Segment>? segments})> _restorePersistedState(
      {bool verify = false}) async {
    final record = await _repository.find(_request.url);
    if (record == null) return (offset: 0, segments: null);
    _createdAt = record.createdAt;

    final existingLength = await _writer.lengthOf(record.filePath);
    if (existingLength == null) {
      await _repository.delete(_request.url);
      return (offset: 0, segments: null);
    }

    _filePath = record.filePath;
    _totalBytes = record.totalBytes;

    final recordSegments = record.segments;
    if (recordSegments != null) {
      // Segmented: the file is pre-allocated, so its length is meaningless —
      // trust the persisted per-segment progress.
      final segments = [
        for (final s in recordSegments) Segment.fromProgress(s),
      ];
      if (verify) await _verifySegments(record.filePath, segments);
      return (offset: 0, segments: segments);
    }

    // Single-stream. Legacy records (no verified byte count) fall back to
    // the file length, like before integrity tracking existed.
    if (!verify || record.downloadedBytes <= 0) {
      return (offset: existingLength, segments: null);
    }
    if (existingLength >= record.downloadedBytes) {
      final crc =
          await _crcOfRange(record.filePath, 0, record.downloadedBytes);
      if (crc != null &&
          (record.crc32 == unknownCrc32 || crc == record.crc32)) {
        _streamCrc = crc;
        return (offset: record.downloadedBytes, segments: null);
      }
    }
    // Truncated or modified while paused — the prefix can't be trusted.
    await _writer.delete(record.filePath);
    _streamCrc = 0;
    return (offset: 0, segments: null);
  }

  /// Re-checks each segment's on-disk bytes against its stored CRC-32 and
  /// resets the ones that no longer match, so only damaged ranges are
  /// downloaded again.
  Future<void> _verifySegments(String path, List<Segment> segments) async {
    for (final segment in segments) {
      if (segment.downloaded == 0) continue;
      final crc = await _crcOfRange(path, segment.start, segment.downloaded);
      if (crc == null) {
        segment.reset(); // file shorter than this segment's data
      } else if (segment.crc == unknownCrc32) {
        segment.crc = crc; // legacy record — adopt and verify from now on
      } else if (crc != segment.crc) {
        segment.reset(); // data was modified while paused
      }
    }
  }

  /// CRC-32 of `[start, start + length)` of the file, or `null` when the
  /// file does not contain that many bytes.
  Future<int?> _crcOfRange(String path, int start, int length) async {
    if (length <= 0) return 0;
    var crc = 0;
    var read = 0;
    await for (final chunk in _writer.read(path, start, start + length)) {
      crc = crc32Update(crc, chunk);
      read += chunk.length;
    }
    return read == length ? crc : null;
  }

  /// Persists single-stream progress (verified byte count + checksum) so a
  /// later resume can validate the on-disk data.
  Future<void> _persistSingleStream() async {
    final path = _filePath;
    if (path == null || _totalBytes <= 0) return;
    _createdAt ??= DateTime.now();
    await _repository.put(DownloadRecord(
      url: _request.url,
      filePath: path,
      totalBytes: _totalBytes,
      createdAt: _createdAt!,
      downloadedBytes: _downloadedBytes,
      crc32: _streamCrc,
    ));
  }

  Future<DownloadConnection> _openWithRetry(int offset) async {
    var attempt = 0;
    while (true) {
      try {
        return await _client.open(_request, startByte: offset);
      } catch (error) {
        attempt++;
        final delay = _retryPolicy.delayBeforeRetry(attempt, error);
        if (delay == null) rethrow;
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Name priority: caller's choice → server suggestion
  /// (`Content-Disposition`) → last URL path segment → timestamp.
  String _resolveFilePath(DownloadConnection connection) {
    var name = _request.fileName ??
        connection.suggestedFileName ??
        _fileNameFromUrl() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final extension = connection.fileExtension;
    if (extension != null && p.extension(name).isEmpty) {
      name = '$name.$extension';
    }
    return p.join(_request.directory, name);
  }

  String? _fileNameFromUrl() {
    final segments = Uri.tryParse(_request.url)?.pathSegments;
    if (segments == null || segments.isEmpty) return null;
    final name = segments.last.trim();
    return name.isEmpty ? null : name;
  }

  /// Shared progress bookkeeping for both download modes.
  void _recordProgress(List<int> chunk) {
    _downloadedBytes += chunk.length;
    _retryAttempt = 0; // progress was made — reset the retry budget
    _interceptors.notifyChunk(this, chunk);

    final speedUpdated = _speed.addBytes(chunk.length);
    if (speedUpdated || _emitWatch.elapsed >= progressInterval) {
      _emitWatch
        ..reset()
        ..start();
      _emit(_progress.copyWith(
        downloadedBytes: _downloadedBytes,
        bytesPerSecond: _speed.bytesPerSecond,
      ));
    }
  }

  void _onChunk(List<int> chunk) {
    _writer.write(chunk);
    if (verifyOnResume) _streamCrc = crc32Update(_streamCrc, chunk);
    _recordProgress(chunk);
    if (_persistWatch.elapsed >= _statePersistInterval) {
      _persistWatch
        ..reset()
        ..start();
      unawaited(_persistSingleStream());
    }
    final delay = _throttle.consume(chunk.length);
    if (delay != null) _subscription?.pause(Future<void>.delayed(delay));
  }

  Future<void> _onDone() async {
    await _closeIO();
    await _complete();
  }

  Future<void> _complete() async {
    _emit(_progress.copyWith(
      status: DownloadStatus.completed,
      downloadedBytes: _downloadedBytes,
      totalBytes: _totalBytes,
      bytesPerSecond: null,
    ));
    await _interceptors.notifyComplete(this);
  }

  Future<void> _onStreamError(Object error, StackTrace stackTrace) async {
    await _closeIO();
    if (_disposed) return;

    // Mid-transfer drop: ask the retry policy, then resume from the bytes
    // already on disk instead of starting over.
    final delay = _retryPolicy.delayBeforeRetry(++_retryAttempt, error);
    if (delay != null) {
      await Future<void>.delayed(delay);
      if (_disposed || !status.isActive) return;
      try {
        await _run();
        return;
      } catch (runError, runStackTrace) {
        await _fail(runError, runStackTrace);
        return;
      }
    }
    await _fail(error, stackTrace);
  }

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    await _closeIO();
    _emit(_progress.copyWith(
      status: DownloadStatus.failed,
      bytesPerSecond: null,
      error: error,
    ));
    await _interceptors.notifyError(this, error, stackTrace);
  }

  Future<void> _closeIO() async {
    _speed.stop();
    _emitWatch.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _connection?.close();
    _connection = null;
    final downloaders = _segmentDownloaders;
    if (downloaders != null) {
      await Future.wait(downloaders.map((d) => d.stop()));
      await _persistSegments();
    } else if (_segments == null && _downloadedBytes > 0) {
      // Single-stream: persist the exact verified offset + checksum.
      await _persistSingleStream();
    }
    await _writer.close();
  }

  void _emit(DownloadProgress progress) {
    _progress = progress;
    if (!_controller.isClosed) _controller.add(progress);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw const DisposedTaskException();
  }
}
