/// Token-bucket bandwidth limiter.
///
/// One instance is shared by all connections of a [DownloadTask] (including
/// every segment of a segmented download), so the configured limit caps the
/// *total* transfer speed. A `null` rate means unlimited — full speed.
///
/// The limit can be changed while a download is running via
/// [DownloadTask.speedLimit].
class BandwidthThrottle {
  BandwidthThrottle({int? bytesPerSecond}) : _bytesPerSecond = bytesPerSecond;

  final Stopwatch _watch = Stopwatch()..start();
  int? _bytesPerSecond;
  double _allowance = 0;
  int _lastMicros = 0;
  bool _primed = false;

  /// Maximum bytes per second, or `null` for unlimited.
  int? get bytesPerSecond => _bytesPerSecond;

  set bytesPerSecond(int? value) {
    _bytesPerSecond = value;
    // Restart accounting so an old surplus/deficit doesn't distort the new
    // rate.
    _allowance = 0;
    _primed = true;
    _lastMicros = _watch.elapsedMicroseconds;
  }

  /// Registers [bytes] as consumed and returns how long the caller must
  /// pause its stream to honor the rate — or `null` when no pause is needed.
  Duration? consume(int bytes) {
    final rate = _bytesPerSecond;
    if (rate == null || rate <= 0) return null;

    final nowMicros = _watch.elapsedMicroseconds;
    if (!_primed) {
      // First consumption with a limit: start with a full one-second burst.
      _allowance = rate.toDouble();
      _primed = true;
    } else {
      _allowance += (nowMicros - _lastMicros) * rate / 1e6;
      // Cap the burst at one second worth of bytes.
      if (_allowance > rate) _allowance = rate.toDouble();
    }
    _lastMicros = nowMicros;

    _allowance -= bytes;
    if (_allowance >= 0) return null;
    return Duration(microseconds: (-_allowance * 1e6 / rate).round());
  }
}
