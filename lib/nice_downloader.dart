/// A clean, extensible file downloader for Flutter.
///
/// Features pause / resume / cancel, resume-after-restart persistence,
/// pluggable retry policies and an interceptor pipeline that lets you hook
/// into every step of a download's lifecycle.
///
/// Entry point: [DownloadManager].
library nice_downloader;

// Core models
export 'src/core/download_progress.dart';
export 'src/core/download_request.dart';
export 'src/core/download_status.dart';
export 'src/core/exceptions.dart';

// Engine
export 'src/engine/bandwidth_throttle.dart';
export 'src/engine/download_task.dart';
export 'src/engine/segment.dart';
export 'src/engine/segment_planner.dart';

// Interceptors
export 'src/interceptors/download_interceptor.dart'
    show DownloadInterceptor;
export 'src/interceptors/logging_interceptor.dart';

// IO
export 'src/io/file_writer.dart';

// Manager
export 'src/manager/download_config.dart';
export 'src/manager/download_manager.dart';

// Network strategies
export 'src/network/connectivity_checker.dart';
export 'src/network/download_client.dart';
export 'src/network/http_download_client.dart';
export 'src/network/retry_policy.dart';

// Storage
export 'src/storage/download_record.dart' show DownloadRecord, SegmentProgress;
export 'src/storage/download_repository.dart';
export 'src/storage/hive_download_repository.dart';
export 'src/storage/in_memory_download_repository.dart';

// Utilities
export 'src/utils/byte_format.dart';
