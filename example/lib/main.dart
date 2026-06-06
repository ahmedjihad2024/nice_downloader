import 'package:flutter/material.dart';

import 'src/home_page.dart';
import 'src/theme.dart';

void main() => runApp(const DownloadManagerApp());

class DownloadManagerApp extends StatelessWidget {
  const DownloadManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nice Downloader',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomePage(),
    );
  }
}
