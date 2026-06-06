// Live-network verification — skipped by default so the suite stays offline.
// Run manually with:
//   flutter test --run-skipped test/real_network_check.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nice_downloader/nice_downloader.dart';

/// Wraps the real HTTP client to record every connection it opens.
class CountingClient extends DownloadClient {
  final HttpDownloadClient _inner = const HttpDownloadClient();
  final List<({int start, int? end})> ranges = [];

  @override
  Future<DownloadConnection> open(DownloadRequest request,
      {required int startByte}) {
    ranges.add((start: startByte, end: request.rangeEnd));
    return _inner.open(request, startByte: startByte);
  }
}

void main() {
  test(
    'LIVE: segmented download against a real server',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('seg_live');
      final client = CountingClient();
      final manager = DownloadManager(
        config: DownloadConfig(
          client: client,
          repository: InMemoryDownloadRepository(),
          segmentPlanner: const DefaultSegmentPlanner(
              maxSegments: 4, minSegmentSize: 1024 * 1024),
        ),
      );

      final task = await manager.createDownload(
        url: 'https://proof.ovh.net/files/10Mb.dat',
        directory: tempDir.path,
        fileName: 'live_check',
      );

      final stopwatch = Stopwatch()..start();
      await task.start();
      final status = task.status.isFinished
          ? task.status
          : (await task.progressStream
                  .firstWhere((p) => p.status.isFinished))
              .status;
      stopwatch.stop();

      final fileLength = await File(task.filePath!).length();
      // ignore: avoid_print
      print('--- LIVE RESULT ---');
      // ignore: avoid_print
      print('status        : $status');
      // ignore: avoid_print
      print('reported total: ${task.progress.totalBytes} bytes');
      // ignore: avoid_print
      print('file on disk  : $fileLength bytes');
      // ignore: avoid_print
      print('connections   : ${client.ranges.length}');
      // ignore: avoid_print
      print('ranges        : ${client.ranges}');
      // ignore: avoid_print
      print('elapsed       : ${stopwatch.elapsedMilliseconds} ms');

      expect(status, DownloadStatus.completed);
      expect(fileLength, task.progress.totalBytes);
      await tempDir.delete(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: 'Live network check — run with --run-skipped',
  );
}
