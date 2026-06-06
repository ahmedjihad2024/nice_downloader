import '../storage/download_record.dart';

/// One byte range of a segmented download.
///
/// Mutable by design: the engine increments [downloaded] as bytes arrive.
/// [SegmentProgress] is the immutable snapshot persisted to storage.
class Segment {
  Segment({
    required this.start,
    required this.end,
    this.downloaded = 0,
    this.crc = 0,
  }) : assert(end >= start, 'end must be >= start');

  /// Restores a segment from its persisted snapshot.
  factory Segment.fromProgress(SegmentProgress progress) => Segment(
        start: progress.start,
        end: progress.end,
        downloaded: progress.downloaded,
        crc: progress.crc32,
      );

  /// First byte of the range (inclusive).
  final int start;

  /// Last byte of the range (inclusive).
  final int end;

  /// Bytes of this range already written to disk.
  int downloaded;

  /// Running CRC-32 of the first [downloaded] bytes, used to verify the
  /// on-disk data before resuming. [unknownCrc32] for legacy records.
  int crc;

  /// Total size of the range.
  int get length => end - start + 1;

  /// The absolute file offset the next byte must be written at.
  int get nextByte => start + downloaded;

  /// Whether the whole range has been downloaded.
  bool get isComplete => downloaded >= length;

  /// Resets the segment to "nothing downloaded" — used when its on-disk
  /// data failed integrity verification.
  void reset() {
    downloaded = 0;
    crc = 0;
  }

  /// Immutable snapshot for persistence.
  SegmentProgress toProgress() => SegmentProgress(
      start: start, end: end, downloaded: downloaded, crc32: crc);

  @override
  String toString() => 'Segment($start-$end, $downloaded/$length)';
}
