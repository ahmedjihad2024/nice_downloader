import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../core/exceptions.dart';
import 'download_record.dart';
import 'download_repository.dart';

/// Default [DownloadRepository] persisting records in a Hive CE box.
///
/// The box is opened lazily on first use; no explicit init call is required.
class HiveDownloadRepository implements DownloadRepository {
  HiveDownloadRepository({String boxName = defaultBoxName})
      : _boxName = boxName;

  /// Default name of the Hive box holding download records.
  static const String defaultBoxName = 'nice_downloader_records';

  final String _boxName;
  Box<DownloadRecord>? _box;

  Future<Box<DownloadRecord>> _openBox() async {
    final box = _box;
    if (box != null && box.isOpen) return box;

    try {
      try {
        await Hive.initFlutter();
      } catch (_) {
        // Not running inside Flutter (e.g. pure Dart tests).
        Hive.init(Directory.systemTemp.path);
      }
      if (!Hive.isAdapterRegistered(downloadRecordTypeId)) {
        Hive.registerAdapter(DownloadRecordAdapter());
      }
      return _box = await Hive.openBox<DownloadRecord>(_boxName);
    } catch (e) {
      throw StorageException('Failed to open Hive box "$_boxName".', cause: e);
    }
  }

  @override
  Future<DownloadRecord?> find(String url) async =>
      (await _openBox()).get(url);

  @override
  Future<void> put(DownloadRecord record) async =>
      (await _openBox()).put(record.url, record);

  @override
  Future<void> delete(String url) async => (await _openBox()).delete(url);

  @override
  Future<List<DownloadRecord>> findAll() async =>
      (await _openBox()).values.toList(growable: false);
}
