import '../engine/segment_planner.dart';
import '../interceptors/download_interceptor.dart';
import '../io/file_writer.dart';
import '../network/connectivity_checker.dart';
import '../network/download_client.dart';
import '../network/http_download_client.dart';
import '../network/retry_policy.dart';
import '../storage/download_repository.dart';

/// Default factory for [DownloadConfig.fileWriterFactory].
DownloadFileWriter defaultFileWriterFactory() => RandomAccessFileWriter();

/// Configuration shared by all downloads created from one [DownloadManager].
///
/// Every collaborator is an abstraction with a sensible default, so behavior
/// is extended by injecting implementations — not by editing the engine:
///
/// ```dart
/// final manager = DownloadManager(
///   config: DownloadConfig(
///     interceptors: [LoggingInterceptor(), MyAnalyticsInterceptor()],
///     retryPolicy: ExponentialBackoffRetryPolicy(maxRetries: 5),
///     waitForConnection: true,
///   ),
/// );
/// ```
class DownloadConfig {
  const DownloadConfig({
    this.interceptors = const [],
    this.client = const HttpDownloadClient(),
    this.connectivityChecker = const DnsConnectivityChecker(),
    this.retryPolicy = const ExponentialBackoffRetryPolicy(),
    this.repository,
    this.fileWriterFactory = defaultFileWriterFactory,
    this.segmentPlanner = const DefaultSegmentPlanner(),
    this.speedLimit,
    this.waitForConnection = false,
    this.verifyOnResume = true,
    this.progressInterval = const Duration(milliseconds: 100),
    this.connectionStagger = const Duration(milliseconds: 200),
  });

  /// Inspect / modify every step of every download, in order.
  final List<DownloadInterceptor> interceptors;

  /// Transport used to open connections. Default: `package:http`.
  final DownloadClient client;

  /// How connectivity is probed. Default: a DNS lookup.
  final ConnectivityChecker connectivityChecker;

  /// When and how failed attempts are retried.
  /// Default: 3 retries with exponential backoff.
  final RetryPolicy retryPolicy;

  /// Where download state is persisted. `null` selects the default
  /// [HiveDownloadRepository]; pass [InMemoryDownloadRepository] to disable
  /// resume-after-restart persistence.
  final DownloadRepository? repository;

  /// Creates the file writer used by each task.
  final DownloadFileWriter Function() fileWriterFactory;

  /// How downloads are split into parallel connections (IDM-style).
  /// Default: up to 8 segments of at least 2 MB each, when the server
  /// supports range requests. Pass [NoSegmentationPlanner] to disable.
  final SegmentPlanner segmentPlanner;

  /// Default total speed cap per download in bytes/second.
  /// `null` (the default) means unlimited — max speed. Can be overridden per
  /// download and changed at runtime via [DownloadTask.speedLimit].
  final int? speedLimit;

  /// When `true`, starting a download while offline waits for connectivity
  /// instead of failing.
  final bool waitForConnection;

  /// When `true` (the default), downloaded bytes are checksummed (CRC-32)
  /// and re-verified before resuming, so data modified or truncated on disk
  /// while paused is detected and only the damaged ranges are fetched again.
  /// Disable to skip the verification read on resume.
  final bool verifyOnResume;

  /// Minimum time between progress events while downloading.
  final Duration progressInterval;

  /// Ramp between opening consecutive segment connections — avoids tripping
  /// per-IP rate limiters by bursting all connections in the same instant.
  final Duration connectionStagger;
}
