import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/download_request.dart';
import '../core/exceptions.dart';
import 'download_client.dart';

/// Parses a `Retry-After` header — either delta-seconds (`"120"`) or an
/// HTTP date — into a duration. Returns `null` when absent or malformed.
Duration? parseRetryAfter(String? headerValue) {
  if (headerValue == null) return null;
  final seconds = int.tryParse(headerValue.trim());
  if (seconds != null) {
    return seconds < 0 ? null : Duration(seconds: seconds);
  }
  try {
    final until = HttpDate.parse(headerValue).difference(DateTime.now());
    return until.isNegative ? Duration.zero : until;
  } on Object {
    return null;
  }
}

/// MIME subtypes that carry no real file-type information — using them as a
/// file extension (e.g. `video.octet-stream`) would be wrong.
const Set<String> _genericMimeSubtypes = {
  'octet-stream',
  'force-download',
  'x-download',
  'download',
  'binary',
};

/// Derives a usable file extension from a `Content-Type` header, e.g.
/// `"video/mp4; charset=utf-8"` → `"mp4"`. Returns `null` for missing or
/// generic types like `application/octet-stream`.
String? extensionFromContentType(String? contentType) {
  if (contentType == null) return null;
  final mime = contentType.split(';').first.trim();
  final parts = mime.split('/');
  if (parts.length != 2 || parts[1].isEmpty) return null;
  final subtype = parts[1].toLowerCase();
  return _genericMimeSubtypes.contains(subtype) ? null : subtype;
}

/// Default [DownloadClient] backed by `package:http`.
///
/// Always issues a `Range` request so resume support can be detected from the
/// status code (206 vs 200).
class HttpDownloadClient extends DownloadClient {
  const HttpDownloadClient({this.userAgent = defaultUserAgent});

  /// Browser-like default — some servers reject Dart's built-in user agent.
  /// Note: sites behind JavaScript challenges (e.g. Cloudflare "Just a
  /// moment…") block all non-browser clients regardless of this header.
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36 NiceDownloader/1';

  /// Sent as `User-Agent` unless the request supplies its own.
  final String userAgent;

  @override
  Future<DownloadConnection> open(DownloadRequest request,
      {required int startByte}) async {
    final client = http.Client();
    try {
      final httpRequest = http.Request('GET', Uri.parse(request.url))
        ..headers['User-Agent'] = userAgent
        ..headers.addAll(request.headers)
        ..headers['Range'] = 'bytes=$startByte-${request.rangeEnd ?? ''}';

      final response = await client.send(httpRequest);
      if (response.statusCode >= 400) {
        throw ServerException(
          response.statusCode,
          retryAfter: parseRetryAfter(response.headers['retry-after']),
        );
      }

      return DownloadConnection(
        byteStream: response.stream,
        contentLength: response.contentLength ?? 0,
        supportsResume: response.statusCode == 206,
        suggestedFileName:
            _fileNameFrom(response.headers['content-disposition']),
        fileExtension:
            extensionFromContentType(response.headers['content-type']),
        onClose: () async => client.close(),
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  String? _fileNameFrom(String? contentDisposition) {
    if (contentDisposition == null) return null;
    final match = RegExp('filename=(?:"([^"]*)"|([^;]+))')
        .firstMatch(contentDisposition);
    final name = (match?.group(1) ?? match?.group(2))?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

}
