import 'download_record.dart';

/// Repository abstraction over the download-state store.
///
/// The engine only depends on this interface, so the backing store can be
/// swapped (Hive, SQLite, in-memory, …) without touching download logic.
abstract class DownloadRepository {
  /// Returns the record stored for [url], or `null` when none exists.
  Future<DownloadRecord?> find(String url);

  /// Creates or replaces the record for [record.url].
  Future<void> put(DownloadRecord record);

  /// Removes the record for [url]; a missing record is not an error.
  Future<void> delete(String url);

  /// All stored records, e.g. to rebuild a download list on app start.
  Future<List<DownloadRecord>> findAll();
}
