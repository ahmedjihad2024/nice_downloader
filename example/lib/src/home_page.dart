import 'package:flutter/material.dart';
import 'package:nice_downloader/nice_downloader.dart';
import 'package:path_provider/path_provider.dart';

import 'speed_options.dart';
import 'theme.dart';
import 'widgets/add_url_field.dart';
import 'widgets/download_card.dart';

/// Main screen: URL field on top, the list of downloads below, a global
/// speed limit control in the header. Per-card controls handle
/// pause/continue, retry, per-download speed and removal.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// One manager for the whole app — interceptors/policies configured once.
  final DownloadManager _manager = DownloadManager(
    config: const DownloadConfig(
      interceptors: [LoggingInterceptor()],
      waitForConnection: true,
    ),
  );

  final List<DownloadTask> _tasks = [];

  /// Applied to new downloads and, when changed, to the running ones too.
  /// Defaults to max speed (no limit).
  SpeedOption _globalSpeed = SpeedOption.all.first;

  @override
  void initState() {
    super.initState();
    _restorePreviousDownloads();
  }

  /// Rebuilds the list from storage: completed downloads appear with their
  /// green check, partial ones as paused — ready to continue with ▶.
  Future<void> _restorePreviousDownloads() async {
    final restored = await _manager.restorePersistedDownloads();
    if (!mounted || restored.isEmpty) return;
    setState(() => _tasks.addAll(restored));
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  Future<void> _addDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _showMessage('Please enter a valid http(s) link.');
      return;
    }
    if (_tasks.any((task) => task.request.url == url)) {
      _showMessage('This link is already in the list.');
      return;
    }

    final directory =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final task = await _manager.createDownload(
      url: url,
      directory: directory.path,
      speedLimit: _globalSpeed.bytesPerSecond, // null = max speed
    );
    setState(() => _tasks.insert(0, task));
    await task.start();
  }

  Future<void> _removeTask(DownloadTask task) async {
    if (!task.status.isFinished) await task.cancel();
    setState(() => _tasks.remove(task));
    await _manager.remove(task);
  }

  void _applyGlobalSpeed(SpeedOption option) {
    setState(() => _globalSpeed = option);
    for (final task in _tasks) {
      task.speedLimit = option.bytesPerSecond;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _buildHeader(),
                  const SizedBox(height: 20),
                  AddUrlField(onAdd: _addDownload),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _tasks.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return DownloadCard(
                                key: ObjectKey(task),
                                task: task,
                                onRemove: () => _removeTask(task),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.download_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Downloads',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        // Global speed limit — "Max speed" unless the user picks a cap.
        PopupMenuButton<SpeedOption>(
          tooltip: 'Speed limit for all downloads',
          onSelected: _applyGlobalSpeed,
          itemBuilder: (context) => [
            for (final option in SpeedOption.all)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    if (option.label == _globalSpeed.label)
                      const Icon(Icons.check_rounded,
                          size: 16, color: AppColors.accent)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(option.label),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed_rounded,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  _globalSpeed.label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                const Icon(Icons.arrow_drop_down_rounded,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.cloud_download_rounded,
                size: 34, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text(
            'No downloads yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Paste a link above to start downloading.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
