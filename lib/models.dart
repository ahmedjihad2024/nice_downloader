part of 'nice_downloader.dart';

// enum DOWNLOAD_STATUS { Downloading, Pause, Failed, Canceled, Completed, LoadingProgress }
//
// class DownloaderData {
//   DOWNLOAD_STATUS downloadStatus;
//   int downloadedBytes;
//   int totalBytes;
//   double percent = 0;
//   String downloadSpeed;
//   DownloaderData(
//       {required this.downloadStatus,
//         required this.downloadedBytes,
//         required this.totalBytes,
//         this.downloadSpeed = 'none'}) {
//     percent = double.parse((downloadedBytes * 100 / totalBytes).toStringAsFixed(2));
//     if (percent.isNaN) percent = 0;
//   }
//
//   DownloaderData copyWith(
//       {DOWNLOAD_STATUS? downloadStatus, int? downloadedBytes, int? totalBytes, String? downloadSpeed}) {
//     this.downloadStatus = downloadStatus ?? this.downloadStatus;
//     this.downloadedBytes = downloadedBytes ?? this.downloadedBytes;
//     this.totalBytes = totalBytes ?? this.totalBytes;
//     this.downloadSpeed = downloadSpeed ?? this.downloadSpeed;
//     percent = double.parse((this.downloadedBytes * 100 / this.totalBytes).toStringAsFixed(2));
//     if (percent.isNaN) percent = 0;
//     return this;
//   }
// }
//
// class DownloadProperties {
//   http.Client? httpClient;
//   http.StreamedResponse? response;
//   String? fileExtension;
//   String? filePath;
//   RandomAccessFile? randomAccessFile;
//   int? totalSize;
//   StreamSubscription<List<int>>? downloadingStream;
//   StreamController<DownloaderData>? streamController;
//   DownloaderData? downloaderData;
//   int currentDownload = 0;
//   bool waitConnection = false;
//   bool noConnection = false;
//   String? url;
//   String? downloadPath;
//   String? fileName;
//   int from = 0;
//   int? to;
//   bool done = false;
//
//   Future<void> closeStreamController() async {
//     // Close StreamController
//     await streamController?.close();
//     streamController = null;
//   }
//
//   Future<void> closeHttpClient() async {
//     // Close HttpClient
//     httpClient?.close();
//     httpClient = null;
//   }
//
//   Future<void> closeRandomAccessFile() async {
//     // Close RandomAccessFile
//     await randomAccessFile?.close();
//     randomAccessFile = null;
//   }
//
//   Future<void> closeDownloadingStream() async {
//     // Close Download Stream
//     await downloadingStream?.cancel();
//     downloadingStream = null;
//   }
//
//   Future<void> deleteRandomAccessFile() async => await File(filePath!).delete();
// }

enum DOWNLOAD_STATUS {
  LOADING,
  DOWNLOADING,
  COMPLETED,
  FAILED,
  CANCELED,
  PAUSED,
  WAITING
}

class DownloaderData {
  DOWNLOAD_STATUS downloadStatus;
  int downloadedBytes;
  int totalBytes;
  ({double speed, String type})? downloadSpeed;

  DownloaderData({
    required this.downloadStatus,
    required this.downloadedBytes,
    required this.totalBytes,
    this.downloadSpeed,
  });

  // Add a copyWith method for easy updates
  DownloaderData copyWith({
    DOWNLOAD_STATUS? downloadStatus,
    int? downloadedBytes,
    int? totalBytes,
    ({double speed, String type})? downloadSpeed,
  }) {
    this.downloadStatus = downloadStatus ?? this.downloadStatus;
    this.downloadedBytes = downloadedBytes ?? this.downloadedBytes;
    this.totalBytes = totalBytes ?? this.totalBytes;
    this.downloadSpeed = downloadSpeed ?? this.downloadSpeed;
    return this;
  }

  // Helper to calculate percentage
  // double get percent =>  double.parse((downloadedBytes * 100 / totalBytes).toStringAsFixed(2)).isNaN;
  double get percent {
    double percent = ((downloadedBytes / totalBytes) * 100);
    return percent.isNaN ? 0 : double.parse(percent.toStringAsFixed(2));
  }
}

class UrlDetails {
  final http.Client httpClient;
  final http.StreamedResponse streamedResponse;
  final String fileName;
  final String fileExtension;
  final int totalBytes;

  UrlDetails(
      {required this.httpClient,
      required this.streamedResponse,
      required this.fileExtension,
      required this.fileName,
      required this.totalBytes});
}
