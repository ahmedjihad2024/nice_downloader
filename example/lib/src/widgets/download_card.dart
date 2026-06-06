import 'package:flutter/material.dart';
import 'package:nice_downloader/nice_downloader.dart';

import '../speed_options.dart';
import '../theme.dart';

/// One download in the list: file info, progress bar, live speed, status,
/// pause/continue, per-download speed limit and remove.
class DownloadCard extends StatelessWidget {
  const DownloadCard({super.key, required this.task, required this.onRemove});

  final DownloadTask task;
  final VoidCallback onRemove;

  String get _displayName {
    final path = task.filePath;
    if (path != null) return path.split(RegExp(r'[\\/]')).last;
    final segments = Uri.tryParse(task.request.url)?.pathSegments;
    if (segments != null && segments.isNotEmpty) return segments.last;
    return task.request.url;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadProgress>(
      stream: task.progressStream,
      initialData: task.progress,
      builder: (context, snapshot) {
        final progress = snapshot.data!;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _FileIcon(status: progress.status),
              const SizedBox(width: 14),
              Expanded(child: _buildDetails(progress)),
              const SizedBox(width: 8),
              _buildActions(context, progress),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetails(DownloadProgress progress) {
    final speed = progress.readableSpeed;
    final limit = task.speedLimit;
    final detail = switch (progress.status) {
      DownloadStatus.downloading =>
        '${progress.readableDownloaded} of ${progress.readableTotal}'
            '${speed != null ? '  •  $speed' : ''}',
      DownloadStatus.completed => '${progress.readableTotal}  •  Done',
      DownloadStatus.failed => _errorText(progress.error),
      _ => '${progress.readableDownloaded} of ${progress.readableTotal}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _StatusLabel(status: progress.status),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.totalBytes > 0
                ? progress.percent / 100
                : (progress.status.isActive ? null : 0),
            minHeight: 6,
            backgroundColor: AppColors.surfaceLight,
            color: _statusColor(progress.status),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (limit != null) ...[
              const Icon(Icons.speed_rounded,
                  size: 14, color: AppColors.warning),
              const SizedBox(width: 3),
              Text(
                SpeedOption.fromBytes(limit).label,
                style:
                    const TextStyle(color: AppColors.warning, fontSize: 12.5),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              '${progress.percent.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, DownloadProgress progress) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _speedMenu(context),
        const SizedBox(width: 4),
        _primaryAction(progress.status),
        const SizedBox(width: 4),
        _RoundIconButton(
          icon: Icons.close_rounded,
          color: AppColors.textSecondary,
          tooltip: 'Remove',
          onPressed: onRemove,
        ),
      ],
    );
  }

  /// Per-download speed limit. "Max speed" unless the user picks a cap;
  /// applies instantly, even mid-download.
  Widget _speedMenu(BuildContext context) {
    return PopupMenuButton<SpeedOption>(
      tooltip: 'Speed limit',
      icon: const Icon(Icons.speed_rounded,
          size: 20, color: AppColors.textSecondary),
      onSelected: (option) => task.speedLimit = option.bytesPerSecond,
      itemBuilder: (context) => [
        for (final option in SpeedOption.all)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                if (task.speedLimit == option.bytesPerSecond)
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
    );
  }

  Widget _primaryAction(DownloadStatus status) {
    return switch (status) {
      DownloadStatus.connecting => const Padding(
          padding: EdgeInsets.all(10),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.accent,
            ),
          ),
        ),
      DownloadStatus.downloading => _RoundIconButton(
          icon: Icons.pause_rounded,
          color: AppColors.accent,
          tooltip: 'Pause',
          onPressed: task.pause,
        ),
      DownloadStatus.completed => const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 22),
        ),
      DownloadStatus.failed => _RoundIconButton(
          icon: Icons.restart_alt_rounded,
          color: AppColors.danger,
          tooltip: 'Retry',
          onPressed: task.start,
        ),
      _ => _RoundIconButton(
          icon: Icons.play_arrow_rounded,
          color: AppColors.accent,
          tooltip: 'Continue',
          onPressed: task.start,
        ),
    };
  }

  String _errorText(Object? error) => switch (error) {
        NoConnectionException() => 'No internet connection',
        ServerException(statusCode: 403) =>
          'Access denied (403) — this site blocks download managers',
        ServerException(statusCode: 404) => 'File not found (404)',
        ServerException(statusCode: 429) =>
          'Rate limited by server (429) — wait and retry',
        ServerException(statusCode: final code) => 'Server error ($code)',
        _ => 'Download failed',
      };
}

Color _statusColor(DownloadStatus status) => switch (status) {
      DownloadStatus.completed => AppColors.success,
      DownloadStatus.paused => AppColors.warning,
      DownloadStatus.failed || DownloadStatus.canceled => AppColors.danger,
      _ => AppColors.accent,
    };

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.insert_drive_file_rounded, color: color, size: 22),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      DownloadStatus.idle => 'Waiting',
      DownloadStatus.connecting => 'Connecting…',
      DownloadStatus.downloading => 'Downloading',
      DownloadStatus.paused => 'Paused',
      DownloadStatus.completed => 'Completed',
      DownloadStatus.failed => 'Failed',
      DownloadStatus.canceled => 'Canceled',
    };
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: .12),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, color: color, size: 20),
    );
  }
}
