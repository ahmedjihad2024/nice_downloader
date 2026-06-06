import 'segment.dart';

/// Strategy deciding how a download is split into parallel segments
/// (IDM-style multi-connection downloading).
///
/// The engine only segments when the server supports range requests and the
/// total size is known; otherwise it falls back to a single stream
/// regardless of the plan.
abstract class SegmentPlanner {
  const SegmentPlanner();

  /// Splits the byte range `[start, endExclusive)` into segments.
  ///
  /// Returning a single segment (or an empty list) makes the engine use the
  /// plain single-stream path.
  List<Segment> plan({required int start, required int endExclusive});
}

/// Default planner: split into up to [maxSegments] equal parts, but never
/// create a segment smaller than [minSegmentSize] — small files aren't worth
/// the extra connections.
class DefaultSegmentPlanner extends SegmentPlanner {
  const DefaultSegmentPlanner({
    this.maxSegments = 8,
    this.minSegmentSize = 2 * 1024 * 1024, // 2 MB
  })  : assert(maxSegments >= 1, 'maxSegments must be >= 1'),
        assert(minSegmentSize > 0, 'minSegmentSize must be > 0');

  /// Maximum number of parallel connections per download.
  final int maxSegments;

  /// Minimum bytes per segment; below `2 * minSegmentSize` the download
  /// stays single-stream.
  final int minSegmentSize;

  @override
  List<Segment> plan({required int start, required int endExclusive}) {
    final total = endExclusive - start;
    if (total <= 0) return [];

    var count = total ~/ minSegmentSize;
    if (count > maxSegments) count = maxSegments;
    if (count < 2) return [Segment(start: start, end: endExclusive - 1)];

    final size = total ~/ count;
    return [
      for (var i = 0; i < count; i++)
        Segment(
          start: start + i * size,
          // The last segment absorbs the division remainder.
          end: i == count - 1 ? endExclusive - 1 : start + (i + 1) * size - 1,
        ),
    ];
  }
}

/// Disables segmentation entirely — every download uses a single stream.
class NoSegmentationPlanner extends SegmentPlanner {
  const NoSegmentationPlanner();

  @override
  List<Segment> plan({required int start, required int endExclusive}) {
    if (endExclusive <= start) return [];
    return [Segment(start: start, end: endExclusive - 1)];
  }
}
