import 'download_record.dart';
import 'download_repository.dart';

/// A [DownloadRepository] that keeps records in memory only.
///
/// Useful for tests and for apps that don't want resume-after-restart
/// persistence.
class InMemoryDownloadRepository implements DownloadRepository {
  final Map<String, DownloadRecord> _records = {};

  @override
  Future<DownloadRecord?> find(String url) async => _records[url];

  @override
  Future<void> put(DownloadRecord record) async =>
      _records[record.url] = record;

  @override
  Future<void> delete(String url) async => _records.remove(url);

  @override
  Future<List<DownloadRecord>> findAll() async =>
      _records.values.toList(growable: false);
}
