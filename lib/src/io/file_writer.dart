import 'dart:io';

/// Abstraction over the file system used by the download engine.
///
/// One instance is created per stream — a single-stream download uses one
/// writer, a segmented download uses one writer *per segment* (see
/// [DownloadConfig.fileWriterFactory]). Implement it to redirect output —
/// e.g. write to encrypted storage or an in-memory buffer in tests.
abstract class DownloadFileWriter {
  /// Length of the file at [path], or `null` when it does not exist.
  Future<int?> lengthOf(String path);

  /// Opens [path] for writing, creating parent directories when needed.
  /// With [append] the existing content is kept and extended.
  Future<void> open(String path, {required bool append});

  /// Opens [path] for writing at byte offset [position] without truncating —
  /// used by segmented downloads where each segment writes its own region.
  Future<void> openAt(String path, int position);

  /// Grows the file at [path] to [length] bytes (zero-filled), creating it
  /// when needed. Segmented downloads pre-allocate so segments can write at
  /// their offsets immediately.
  Future<void> allocate(String path, int length);

  /// Appends [chunk] at the current position. Called once per network chunk,
  /// so it must be fast; the default implementation writes synchronously.
  void write(List<int> chunk);

  /// Reads bytes `[start, end)` of the file at [path] — used to verify
  /// already-downloaded data against its stored checksum before resuming.
  Stream<List<int>> read(String path, int start, int end);

  /// Flushes pending bytes and closes the file. Safe to call when not open.
  Future<void> close();

  /// Deletes the file at [path]; a missing file is not an error.
  Future<void> delete(String path);
}

/// Default writer backed by [RandomAccessFile] with synchronous chunk writes
/// (fastest option for sequential appends).
class RandomAccessFileWriter implements DownloadFileWriter {
  RandomAccessFile? _file;

  @override
  Future<int?> lengthOf(String path) async {
    final file = File(path);
    return await file.exists() ? file.length() : null;
  }

  @override
  Future<void> open(String path, {required bool append}) async {
    await close();
    final file = File(path);
    await file.parent.create(recursive: true);
    _file = await file.open(
        mode: append ? FileMode.append : FileMode.write);
  }

  @override
  Future<void> openAt(String path, int position) async {
    await close();
    final file = File(path);
    await file.parent.create(recursive: true);
    // FileMode.append: writable without truncating existing content.
    final raf = await file.open(mode: FileMode.append);
    await raf.setPosition(position);
    _file = raf;
  }

  @override
  Future<void> allocate(String path, int length) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.append);
    try {
      if (await raf.length() < length) await raf.truncate(length);
    } finally {
      await raf.close();
    }
  }

  @override
  void write(List<int> chunk) => _file?.writeFromSync(chunk);

  @override
  Stream<List<int>> read(String path, int start, int end) =>
      File(path).openRead(start, end);

  @override
  Future<void> close() async {
    final file = _file;
    _file = null;
    try {
      await file?.close();
    } on FileSystemException {
      // Already closed by the OS — nothing left to release.
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
