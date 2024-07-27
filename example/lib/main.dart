import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nice_downloader/nice_downloader.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late DownloadManager downloadManager;
  late Downloader downloader;
  DownloaderData? data;

  Future<void> init() async {
    downloadManager = DownloadManager();
    downloader = await downloadManager.createDownload(
        url:
            'https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_20mb.mp4',
        downloadPath: (await getDownloadsDirectory())!.path,
        fileName: "test");

    late StreamSubscription<DownloaderData> listener;
    listener = downloader.listen((DownloaderData data) {
      setState(() => this.data = data);
    });

    await downloader.initDownload();
  }

  @override
  void initState() {
    init();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: 200,
                  height: 5,
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  decoration: BoxDecoration(
                      color: Colors.brown.withOpacity(.1),
                      borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    children: [
                      Container(
                        width: data == null ? 0 : data!.percent * 200 / 100,
                        height: 5,
                        color: Colors.brown,
                      ),
                    ],
                  )),
              const SizedBox(
                width: 5,
              ),
              Text(data == null || data!.downloadSpeed == null ? 'Speed: 0' : "Speed ${data!.downloadSpeed?.speed} ${data!.downloadSpeed?.type}"),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("${data?.percent ?? "0.0"} %"),
              const SizedBox(
                width: 5,
              ),
              Text(data?.downloadStatus.name ?? "NONE"),
              const SizedBox(
                width: 5,
              ),
              Text(data == null ? '0' : "${data!.downloadedBytes.formatSize.size} ${data!.downloadedBytes.formatSize.type}"),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (data == null ||
                  data!.downloadStatus != DOWNLOAD_STATUS.LOADING)
                IconButton(
                  onPressed: () async {
                    if (data == null ||
                        data!.downloadStatus == DOWNLOAD_STATUS.FAILED ||
                        data!.downloadStatus == DOWNLOAD_STATUS.CANCELED ||
                        data!.downloadStatus == DOWNLOAD_STATUS.PAUSED || data!.downloadStatus == DOWNLOAD_STATUS.WAITING) {
                      await downloader.start();
                    } else if (data!.downloadStatus ==
                        DOWNLOAD_STATUS.DOWNLOADING) {
                      await downloader.pause();
                    }
                  },
                  icon: Icon(getIcon(data)),
                  color: Colors.brown,
                )
              else ...[
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(
                    backgroundColor: Colors.brown.withOpacity(.1),
                    color: Colors.brown,
                  ),
                )
              ],
              IconButton(
                onPressed: () async {
                  if (data != null) {
                    await downloader.cancel();
                  }
                },
                icon: const Icon(Icons.cancel),
                color: Colors.brown,
              )
            ],
          )
        ],
      ),
    );
  }
}


IconData getIcon(DownloaderData? data){
  IconData iconData;
  if (data == null || data.downloadStatus == DOWNLOAD_STATUS.WAITING || data.downloadStatus == DOWNLOAD_STATUS.CANCELED) {
    iconData = Icons.file_download_outlined;
  } else if (data.downloadStatus == DOWNLOAD_STATUS.DOWNLOADING) {
    iconData = Icons.pause;
  } else if (data.downloadStatus == DOWNLOAD_STATUS.FAILED) {
    iconData = Icons.restart_alt;
  }else {
    iconData = Icons.play_arrow_rounded;
  }
  return iconData;
}
