/// Incremental CRC-32 (IEEE 802.3) used for download integrity tracking.
///
/// Feeding data in pieces produces the same result as hashing it at once:
/// `crc32Update(crc32Update(0, a), b) == crc32Update(0, a + b)`.
library;

final List<int> _table = _buildTable();

List<int> _buildTable() {
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      c = (c & 1) == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c;
  }
  return table;
}

/// Folds [bytes] into a running CRC-32. Start with `crc = 0`.
int crc32Update(int crc, List<int> bytes) {
  var c = crc ^ 0xFFFFFFFF;
  for (var i = 0; i < bytes.length; i++) {
    c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  }
  return c ^ 0xFFFFFFFF;
}
