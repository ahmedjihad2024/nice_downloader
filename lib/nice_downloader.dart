import 'dart:async';
import 'dart:io';

import 'package:hive_flutter/adapters.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'hive_models/download_details.dart';

part 'init_hive.dart';
part 'models.dart';

// Utility class for fetching URL details
class HttpClient {
  Future<UrlDetails> getUrlDetails(String url, int from, [int? to]) async {
    var httpClient = http.Client();
    var httpRequest = http.Request('GET', Uri.parse(url));
    httpRequest.headers.addAll({
      'Range': 'bytes=$from-${to ?? ''}',
    });
    httpRequest.followRedirects = false;
    httpRequest.maxRedirects = 1;
    var streamedResponse = await httpClient.send(httpRequest);

    var contentDisposition = streamedResponse.headers["Content-Disposition"];
    var contentType = streamedResponse.headers['content-type'];

    var fileName = contentDisposition != null
        ? contentDisposition
        .split(';')
        .singleWhere((t) => t.contains("filename"))
        .split("=")[1]
        : DateTime.now().microsecondsSinceEpoch.toString();

    var fileExtension = contentType != null ? contentType.split('/')[1] : 'none';
    var totalBytes = int.parse(streamedResponse.headers['content-length']!);

    return UrlDetails(
      httpClient: httpClient,
      streamedResponse: streamedResponse,
      fileExtension: fileExtension,
      fileName: fileName,
      totalBytes: totalBytes,
    );
  }
}

// Utility class for checking internet connection
class NetworkUtils {
  static Future<bool> checkInternetConnection({bool waitConnection = false}) async {
    while (true) {
      try {
        var response = await http.get(Uri.parse("https://www.google.com/"));
        if (response.statusCode == 200) {
          return true;
        }
      } catch (e) {
        if (waitConnection) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        } else {
          return false;
        }
      }
    }
  }
}

// Utility class for formatting speed
class SpeedFormatter {
  static ({double speed, String type}) formatSpeed(int bytes, double seconds) {
    double speedInBps = bytes / seconds;
    if (speedInBps >= 1024 * 1024) {
      return (
      speed: double.parse((bytes / (1024 * 1024)).toStringAsFixed(2)),
      type: 'Mps'
      );
    } else if (speedInBps >= 1024) {
      return (
      speed: double.parse((bytes / 1024).toStringAsFixed(2)),
      type: 'Kps'
      );
    } else {
      return (speed: bytes.toDouble(), type: 'Bps');
    }
  }
}

// Utility class for formatting byte size
class BytesSize {
  static ({double size, String type}) formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return (
      size: double.parse((bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)),
      type: 'GB'
      );
    } else if (bytes >= 1024 * 1024) {
      return (
      size: double.parse((bytes / (1024 * 1024)).toStringAsFixed(2)),
      type: 'MB'
      );
    } else if (bytes >= 1024) {
      return (
      size: double.parse((bytes / 1024).toStringAsFixed(2)),
      type: 'KB'
      );
    } else {
      return (size: bytes.toDouble(), type: 'Byte');
    }
  }
}

// Extension method for formatting byte size
extension BytesSizeExt on int {
  ({double size, String type}) get formatSize => BytesSize.formatSize(this);
}

// Abstract base class for downloader functionality
abstract class DownloaderBase {
  Future<void> start();
  Future<void> cancel();
  Future<void> pause();
  StreamSubscription<DownloaderData> listen(Function(DownloaderData downloaderData) callback);
}

// Concrete implementation of DownloaderBase
class Downloader implements DownloaderBase {
  String url;
  String downloadPath;
  String? fileName;
  String? filePath;
  int from;
  int? to;
  bool waitConnection;
  int downloadedBytes = 0;
  int totalBytes = 0;
  http.Client? httpClient;
  RandomAccessFile? file;
  StreamSubscription<List<int>>? downloadStream;
  final StreamController<DownloaderData> controller = StreamController<DownloaderData>();
  DownloaderData data;
  Box<DownloadDetails> hiveBox;
  int previousBytes = 0;

  Downloader({
    required this.url,
    required this.downloadPath,
    required this.hiveBox,
    this.fileName,
    this.from = 0,
    this.to,
    this.waitConnection = false,
  }) : data = DownloaderData(
    downloadStatus: DOWNLOAD_STATUS.LOADING,
    downloadedBytes: 0,
    totalBytes: 0,
  );

  Future<void> initDownload() async {
    if (hiveBox.containsKey(url)) {
      var details = hiveBox.get(url)!;
      var fileValidate = File(details.fullPath);
      if (!(await fileValidate.exists())) {
        await fileValidate.create(recursive: true, exclusive: true);
        downloadedBytes = 0;
        from = 0;
        controller.add(data.copyWith(
          downloadStatus: DOWNLOAD_STATUS.WAITING,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ));
      } else {
        int fileLength = await fileValidate.length();
        downloadedBytes = fileLength;
        from = fileLength;
        totalBytes = details.totalBytes;
        filePath = details.fullPath;

        controller.add(data.copyWith(
          downloadStatus: downloadedBytes == totalBytes
              ? DOWNLOAD_STATUS.COMPLETED
              : DOWNLOAD_STATUS.PAUSED,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        ));
      }
    }
  }

  @override
  Future<void> start() async {
    await initDownload();
    if (data.downloadStatus == DOWNLOAD_STATUS.COMPLETED) return;
    controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.LOADING));

    // Check internet connectivity
    var hasInternet = await NetworkUtils.checkInternetConnection(waitConnection: waitConnection);
    if (!hasInternet) {
      controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.FAILED));
      return;
    }

    // Get URL file details
    var urlDetails = await HttpClient().getUrlDetails(url, from, to);
    var fileExtension = urlDetails.fileExtension;
    var response = urlDetails.streamedResponse;
    fileName ??= urlDetails.fileName;
    totalBytes = urlDetails.totalBytes + (hiveBox.containsKey(url) ? from : 0);
    httpClient = urlDetails.httpClient;

    // File validator
    filePath = "$downloadPath\\$fileName.$fileExtension";
    var fileValidate = File(filePath!);
    file = await fileValidate.open(mode: FileMode.append);

    // Save download details in database
    if (!hiveBox.containsKey(url)) {
      hiveBox.put(
          url,
          DownloadDetails(
            fullPath: filePath!,
            millisecondsSinceEpoch: DateTime.now().millisecondsSinceEpoch,
            url: url,
            totalBytes: totalBytes,
          ));
    }

    controller.add(data.copyWith(
      downloadStatus: DOWNLOAD_STATUS.DOWNLOADING,
      totalBytes: totalBytes,
    ));

    try {
      var stopwatch = Stopwatch()..start();
      downloadStream = response.stream.listen((chunk) {
        // stopwatch.stop();
        // var speed = SpeedFormatter.formatSpeed(
        //     chunk.length, (stopwatch.elapsedMicroseconds / 1000000));
        // stopwatch
        //   ..reset()
        //   ..start();

        downloadedBytes += chunk.length;
        file!.writeFromSync(chunk);

        controller.add(data.copyWith(
          downloadedBytes: downloadedBytes,
        ));

        if ((stopwatch.elapsedMicroseconds) > 1000000) { // Update speed every second
          var elapsedSeconds = stopwatch.elapsedMilliseconds / 1000000;
          var speed = SpeedFormatter.formatSpeed(
              (downloadedBytes - previousBytes).toInt(), elapsedSeconds);
          previousBytes = downloadedBytes;
          stopwatch
            ..reset()
            ..start();
          controller.add(data.copyWith(
            downloadSpeed: speed,
          ));
        }

      })
        ..onDone(() async {
          stopwatch.stop();
          await _onDone();
        })
        ..onError((error) async {
          stopwatch.stop();
          controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.FAILED));
          await _handleError();
        });
    } catch (e) {
      controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.FAILED));
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _handleError();
      await _deleteFile();
      downloadedBytes = 0;
      totalBytes = 0;
      controller.add(data.copyWith(
          downloadStatus: DOWNLOAD_STATUS.CANCELED,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
      downloadSpeed: null));
    } catch (e) {
      // Handle cancel error
    }
  }

  @override
  Future<void> pause() async {
    controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.PAUSED));
    await _handleError();
  }

  @override
  StreamSubscription<DownloaderData> listen(Function(DownloaderData downloaderData) callback) =>
      controller.stream.listen(callback);

  Future<void> _onDone() async {
    controller.add(data.copyWith(downloadStatus: DOWNLOAD_STATUS.COMPLETED, downloadSpeed: null));
    await _handleClose();
  }

  Future<void> _handleError() async {
    await _closeDownloadStream();
    await _closeHttpClient();
    await _closeFile();
  }

  Future<void> _closeDownloadStream() async => await downloadStream?.cancel();

  Future<void> _closeHttpClient() async => httpClient?.close();

  Future<void> _closeFile() async {
    try {
      await file?.close();
    } catch (e) {
      // Handle file close error
    }
  }

  Future<void> _deleteFile() async => await File(filePath!).delete();

  Future<void> _handleClose() async {
    await _closeHttpClient();
    await _closeFile();
  }

  Future<void> _closeController() async => await controller.close();

  Future<void> dispose() async => await _closeController();
}

// Factory class for creating Downloader instances
class DownloaderFactory {
  Future<Downloader> create({
    required String url,
    required String downloadPath,
    String? fileName,
    int from = 0,
    int? to,
    bool waitConnection = false,
  }) async {
    return Downloader(
      url: url,
      downloadPath: downloadPath,
      fileName: fileName,
      from: from,
      to: to,
      waitConnection: waitConnection,
      hiveBox: await MyHive().downloadDetails(),
    );
  }
}

// Manager class for handling multiple downloads
class DownloadManager {
  final List<Downloader> _downloads = [];
  final DownloaderFactory _factory = DownloaderFactory();

  Future<Downloader> createDownload({
    required String url,
    required String downloadPath,
    String? fileName,
    int from = 0,
    int? to,
    bool waitConnection = false,
  }) async {
    final downloader = await _factory.create(
      url: url,
      downloadPath: downloadPath,
      fileName: fileName,
      from: from,
      to: to,
      waitConnection: waitConnection,
    );
    _downloads.add(downloader);
    return downloader;
  }

  Future<void> cancelAll() async => Future.wait(_downloads.map((d) => d.cancel()));

  Future<void> pauseAll() async => Future.wait(_downloads.map((d) => d.pause()));

  Future<void> startAll() async => Future.wait(_downloads.map((d) => d.start()));

  List<Downloader> get downloads => _downloads;

  bool remove(Downloader downloader) => _downloads.remove(downloader);
}
