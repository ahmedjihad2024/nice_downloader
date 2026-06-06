import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

/// Hive type id used by [DownloadRecordAdapter]. Keep it unique within your
/// application's Hive type ids.
const int downloadRecordTypeId = 1;

/// Sentinel meaning "no checksum recorded" (records written before
/// integrity tracking existed). On resume such data is adopted as-is.
const int unknownCrc32 = -1;

/// Immutable snapshot of one segment's progress, persisted so a segmented
/// download can resume each segment from its own offset.
@immutable
class SegmentProgress {
  const SegmentProgress({
    required this.start,
    required this.end,
    required this.downloaded,
    this.crc32 = 0,
  });

  /// First byte of the range (inclusive).
  final int start;

  /// Last byte of the range (inclusive).
  final int end;

  /// Bytes of this range already written to disk.
  final int downloaded;

  /// CRC-32 of the first [downloaded] bytes of this range, or [unknownCrc32]
  /// for legacy records.
  final int crc32;

  @override
  String toString() => 'SegmentProgress($start-$end, $downloaded)';
}

/// The persisted state of a download, used to resume after an app restart.
@immutable
class DownloadRecord {
  const DownloadRecord({
    required this.url,
    required this.filePath,
    required this.totalBytes,
    required this.createdAt,
    this.downloadedBytes = 0,
    this.crc32 = 0,
    this.segments,
  });

  /// The remote URL — also the unique key of the record.
  final String url;

  /// Absolute path of the (partial) file on disk.
  final String filePath;

  /// Expected total size in bytes.
  final int totalBytes;

  /// When the download was first created.
  final DateTime createdAt;

  /// Verified progress of a single-stream download. `0` for legacy records
  /// (progress is then inferred from the file length, unverified).
  final int downloadedBytes;

  /// CRC-32 of the first [downloadedBytes] bytes (single-stream only).
  final int crc32;

  /// Per-segment progress for segmented downloads. `null` means the download
  /// is single-stream (a segmented file is pre-allocated, so its length is
  /// meaningless).
  final List<SegmentProgress>? segments;

  @override
  String toString() =>
      'DownloadRecord(url: $url, filePath: $filePath, totalBytes: $totalBytes'
      '${segments != null ? ', segments: ${segments!.length}' : ''})';
}

/// Hand-written Hive adapter — small enough that code generation
/// (`build_runner`) is not worth the build complexity.
///
/// Format history (older records remain readable):
/// * v1: url, filePath, totalBytes, createdAt
/// * v2: v1 + segmentCount (-1 = none) + 3 ints per segment
/// * v3: v1 + marker (-2) + downloadedBytes + crc32
///       + segmentCount (-1 = none) + 4 ints per segment
class DownloadRecordAdapter extends TypeAdapter<DownloadRecord> {
  static const int _v3Marker = -2;

  @override
  int get typeId => downloadRecordTypeId;

  @override
  DownloadRecord read(BinaryReader reader) {
    final url = reader.readString();
    final filePath = reader.readString();
    final totalBytes = reader.readInt();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(reader.readInt());

    var downloadedBytes = 0;
    var crc32 = 0;
    List<SegmentProgress>? segments;

    if (reader.availableBytes > 0) {
      final first = reader.readInt();
      if (first == _v3Marker) {
        downloadedBytes = reader.readInt();
        crc32 = reader.readInt();
        segments = _readSegments(reader, reader.readInt(), withCrc: true);
      } else {
        // v2: `first` is the segment count; no checksums were stored.
        segments = _readSegments(reader, first, withCrc: false);
      }
    }

    return DownloadRecord(
      url: url,
      filePath: filePath,
      totalBytes: totalBytes,
      createdAt: createdAt,
      downloadedBytes: downloadedBytes,
      crc32: crc32,
      segments: segments,
    );
  }

  List<SegmentProgress>? _readSegments(BinaryReader reader, int count,
      {required bool withCrc}) {
    if (count < 0) return null;
    return [
      for (var i = 0; i < count; i++)
        SegmentProgress(
          start: reader.readInt(),
          end: reader.readInt(),
          downloaded: reader.readInt(),
          crc32: withCrc ? reader.readInt() : unknownCrc32,
        ),
    ];
  }

  @override
  void write(BinaryWriter writer, DownloadRecord obj) {
    writer
      ..writeString(obj.url)
      ..writeString(obj.filePath)
      ..writeInt(obj.totalBytes)
      ..writeInt(obj.createdAt.millisecondsSinceEpoch)
      ..writeInt(_v3Marker)
      ..writeInt(obj.downloadedBytes)
      ..writeInt(obj.crc32);

    final segments = obj.segments;
    writer.writeInt(segments?.length ?? -1);
    for (final segment in segments ?? const <SegmentProgress>[]) {
      writer
        ..writeInt(segment.start)
        ..writeInt(segment.end)
        ..writeInt(segment.downloaded)
        ..writeInt(segment.crc32);
    }
  }
}
