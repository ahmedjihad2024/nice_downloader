/// A human readable byte quantity, e.g. `12.34 MB` or `1.2 MB/s`.
class ByteFormat {
  const ByteFormat(this.value, this.unit);

  /// The scaled numeric value (rounded to two decimals).
  final double value;

  /// The unit the value is expressed in (`B`, `KB`, `MB`, `GB`, ...).
  final String unit;

  @override
  String toString() => '$value $unit';
}

const int _kilo = 1024;
const int _mega = 1024 * 1024;
const int _giga = 1024 * 1024 * 1024;

double _round2(double value) => double.parse(value.toStringAsFixed(2));

/// Formats a raw byte count into the largest fitting unit.
ByteFormat formatBytes(num bytes, {String suffix = ''}) {
  if (bytes >= _giga) return ByteFormat(_round2(bytes / _giga), 'GB$suffix');
  if (bytes >= _mega) return ByteFormat(_round2(bytes / _mega), 'MB$suffix');
  if (bytes >= _kilo) return ByteFormat(_round2(bytes / _kilo), 'KB$suffix');
  return ByteFormat(_round2(bytes.toDouble()), 'B$suffix');
}

/// Readable size helpers for byte counts.
extension ReadableBytes on int {
  /// `1536.readableSize` -> `1.5 KB`.
  ByteFormat get readableSize => formatBytes(this);
}

/// Readable speed helpers for bytes-per-second values.
extension ReadableSpeed on double {
  /// `2097152.0.readableSpeed` -> `2.0 MB/s`.
  ByteFormat get readableSpeed => formatBytes(this, suffix: '/s');
}
