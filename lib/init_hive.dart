
part of 'nice_downloader.dart';

class MyHive {
  MyHive._internal();

  static final MyHive _instance = MyHive._internal();

  factory MyHive() => _instance;

  Box<DownloadDetails>? _downloadDetailsBox;

  Future<void> _init() async {
    try {
      await Hive.initFlutter();
    } catch (e) {
      Hive.init((await getApplicationDocumentsDirectory()).path);
    }
  }

  Future<Box<DownloadDetails>> downloadDetails() async {
    if (_downloadDetailsBox != null) {
      return _downloadDetailsBox!;
    }

    await _init();
    Hive.registerAdapter(DownloadDetailsAdapter());
    _downloadDetailsBox = await Hive.openBox<DownloadDetails>('authentication-box');
    return _downloadDetailsBox!;
  }
}