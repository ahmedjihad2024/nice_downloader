import 'package:meta/meta.dart';

/// An immutable description of *what* to download and *where* to put it.
///
/// Interceptors receive the request in [DownloadInterceptor.onCreate] and may
/// return a modified copy (extra headers, different directory, renamed file…)
/// before the task is built.
@immutable
class DownloadRequest {
  const DownloadRequest({
    required this.url,
    required this.directory,
    this.fileName,
    this.headers = const {},
    this.rangeEnd,
  });

  /// The remote file location.
  final String url;

  /// Local directory the file is saved into.
  final String directory;

  /// Optional file name (without extension). When `null`, the name suggested
  /// by the server (`Content-Disposition`) or a timestamp is used.
  final String? fileName;

  /// Extra HTTP headers sent with the request (e.g. authorization).
  final Map<String, String> headers;

  /// Optional inclusive end byte for partial downloads.
  final int? rangeEnd;

  /// Returns a copy of this request with the given fields replaced.
  DownloadRequest copyWith({
    String? url,
    String? directory,
    String? fileName,
    Map<String, String>? headers,
    int? rangeEnd,
  }) {
    return DownloadRequest(
      url: url ?? this.url,
      directory: directory ?? this.directory,
      fileName: fileName ?? this.fileName,
      headers: headers ?? this.headers,
      rangeEnd: rangeEnd ?? this.rangeEnd,
    );
  }

  @override
  String toString() => 'DownloadRequest(url: $url, directory: $directory'
      '${fileName != null ? ', fileName: $fileName' : ''})';
}
