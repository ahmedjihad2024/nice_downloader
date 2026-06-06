/// A selectable speed limit. `bytesPerSecond == null` means unlimited.
class SpeedOption {
  const SpeedOption(this.label, this.bytesPerSecond);

  final String label;
  final int? bytesPerSecond;

  static const int _kb = 1024;
  static const int _mb = 1024 * 1024;

  /// Default is "Max speed" — used whenever the user picks nothing.
  static const List<SpeedOption> all = [
    SpeedOption('Max speed', null),
    SpeedOption('8 MB/s', 8 * _mb),
    SpeedOption('4 MB/s', 4 * _mb),
    SpeedOption('2 MB/s', 2 * _mb),
    SpeedOption('1 MB/s', _mb),
    SpeedOption('512 KB/s', 512 * _kb),
    SpeedOption('256 KB/s', 256 * _kb),
  ];

  /// The option matching [bytesPerSecond], falling back to "Max speed".
  static SpeedOption fromBytes(int? bytesPerSecond) => all.firstWhere(
        (option) => option.bytesPerSecond == bytesPerSecond,
        orElse: () => all.first,
      );
}
