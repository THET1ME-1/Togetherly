import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/data_export.dart';
import 'offline/local_store.dart';
import 'pocketbase_service.dart';

/// Архив «мои данные»: копия того, что приложение хранит о человеке.
///
/// Право забрать такую копию даёт закон Республики Молдова № 133/2011 и GDPR,
/// а политика конфиденциальности обещает его прямым текстом. Собираем из
/// местного хранилища: там уже лежит всё, что пришло с сервера, и не нужно
/// заводить ради выгрузки отдельный роут.
class DataExportService {
  DataExportService._();
  static final DataExportService instance = DataExportService._();
  factory DataExportService() => instance;

  /// Что попадает в архив. Ключ — раздел архива, значение — коллекция кэша.
  static const Map<String, String> sections = {
    'profile': 'users',
    'messages': 'chat_messages',
    'memories': 'memories',
    'wishes': 'wishes',
    'wish_categories': 'wish_categories',
    'moods': 'moods',
    'cycle': 'cycle_entries',
    'timers': 'timers',
    'watch_videos': 'watch_videos',
  };

  /// Собирает архив и возвращает путь к файлу. Null — собрать не удалось.
  Future<String?> buildArchive() async {
    try {
      final uid = PocketBaseService().userId ?? '';
      final data = <String, List<Map<String, dynamic>>>{};
      for (final entry in sections.entries) {
        final records = await LocalStore.instance.allRecords(entry.value);
        data[entry.key] = [
          for (final r in records)
            {'id': r.id, ...Map<String, dynamic>.from(r.data)},
        ];
      }

      final info = await PackageInfo.fromPlatform();
      final bundle = buildExportBundle(
        takenAt: DateTime.now(),
        appVersion: '${info.version}+${info.buildNumber}',
        uid: uid,
        sections: data,
      );

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/togetherly-data-$stamp.json');
      // Отступ намеренный: архив открывают глазами, а не машиной.
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(bundle));
      return file.path;
    } catch (e) {
      debugPrint('DataExportService.buildArchive failed: $e');
      return null;
    }
  }
}
