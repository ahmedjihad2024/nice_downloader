/// Measures transfer speed over fixed time windows.
///
/// Bytes are accumulated until at least [window] has elapsed, then the speed
/// is recomputed — giving a stable, UI-friendly value instead of per-chunk
/// noise.
class SpeedTracker {
  SpeedTracker({this.window = const Duration(seconds: 1)});

  /// Minimum measurement window between speed updates.
  final Duration window;

  final Stopwatch _stopwatch = Stopwatch();
  int _bytesInWindow = 0;
  double? _bytesPerSecond;

  /// Current speed in bytes/second, or `null` before the first window closes.
  double? get bytesPerSecond => _bytesPerSecond;

  /// Starts (or restarts) measuring.
  void start() {
    _bytesInWindow = 0;
    _stopwatch
      ..reset()
      ..start();
  }

  /// Records [count] received bytes. Returns `true` when the speed value was
  /// just refreshed (i.e. a good moment to emit a progress update).
  bool addBytes(int count) {
    _bytesInWindow += count;
    final elapsedMicroseconds = _stopwatch.elapsedMicroseconds;
    if (elapsedMicroseconds < window.inMicroseconds) return false;

    _bytesPerSecond =
        _bytesInWindow * Duration.microsecondsPerSecond / elapsedMicroseconds;
    _bytesInWindow = 0;
    _stopwatch
      ..reset()
      ..start();
    return true;
  }

  /// Stops measuring and clears the current value.
  void stop() {
    _stopwatch.stop();
    _bytesPerSecond = null;
  }
}
