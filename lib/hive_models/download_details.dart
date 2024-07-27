

import 'package:hive/hive.dart';

part 'download_details.g.dart';

@HiveType(typeId: 1)
class DownloadDetails{
  DownloadDetails({required this.fullPath, required this.millisecondsSinceEpoch, required this.url, required this.totalBytes});

  @HiveField(0)
  String fullPath;

  @HiveField(1)
  int millisecondsSinceEpoch;

  @HiveField(2)
  String url;

  @HiveField(3)
  int totalBytes;

}