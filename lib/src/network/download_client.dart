import '../core/download_request.dart';

/// An open connection to the remote file: a byte stream plus the metadata
/// needed to name the file and track progress.
class DownloadConnection {
  DownloadConnection({
    required this.byteStream,
    required this.contentLength,
    required this.supportsResume,
    this.suggestedFileName,
    this.fileExtension,
    Future<void> Function()? onClose,
  }) : _onClose = onClose;

  /// The remote file bytes, starting at the requested offset.
  final Stream<List<int>> byteStream;

  /// Number of bytes this connection will deliver (for the requested range).
  /// `0` when the server did not report a length.
  final int contentLength;

  /// Whether the server honored the range request (HTTP 206). When `false`
  /// the stream always starts at byte 0, regardless of the requested offset.
  final bool supportsResume;

  /// File name suggested by the server (`Content-Disposition`), if any.
  final String? suggestedFileName;

  /// File extension derived from `Content-Type`, if any.
  final String? fileExtension;

  final Future<void> Function()? _onClose;

  /// Releases the underlying transport resources.
  Future<void> close() async => _onClose?.call();
}

/// Strategy for opening connections to remote files.
///
/// The default is [HttpDownloadClient]; provide your own implementation to
/// add custom transports, proxies, mocking in tests, etc.
abstract class DownloadClient {
  const DownloadClient();

  /// Opens a connection delivering [request]'s bytes starting at [startByte]
  /// (inclusive) up to [DownloadRequest.rangeEnd] when set.
  Future<DownloadConnection> open(DownloadRequest request,
      {required int startByte});
}
