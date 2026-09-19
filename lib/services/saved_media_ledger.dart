import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_media.dart';

/// Какие файлы воспоминаний уже лежат в галерее ЭТОГО телефона.
///
/// Нужен двум вещам: разделённая кнопка показывает, сколько осталось, а
/// «Сохранить всё» пропускает уже сохранённое — второе нажатие не плодит
/// копий. Хранится по ключу файла ([mediaKey]), а не по ссылке: токен в адресе
/// меняется каждые полторы минуты.
///
/// Это память устройства, а не аккаунта: на новом телефоне галерея пустая, и
/// сохранять надо заново. Удалил человек кадр из галереи сам — журнал об этом
/// не узнает; тогда кадр сохраняется из «Выбрать кадры», где уже сохранённые
/// только отмечены, а не заперты.
class SavedMediaLedger extends ChangeNotifier {
  SavedMediaLedger._() : limit = 20000;

  @visibleForTesting
  SavedMediaLedger.forTest({this.limit = 20000});

  static final SavedMediaLedger instance = SavedMediaLedger._();

  static const String prefsKey = 'saved_media_keys_v1';

  /// Потолок журнала. У самой активной пары 421 кадр, так что двадцати тысяч
  /// хватит на годы; дальше вытесняется самое старое.
  final int limit;

  // Порядок вставки = порядок свежести: повторное добавление переносит ключ в
  // конец, вытесняется начало.
  final LinkedHashSet<String> _keys = LinkedHashSet<String>();
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _keys
        ..clear()
        ..addAll(prefs.getStringList(prefsKey) ?? const []);
    } catch (e) {
      debugPrint('SavedMediaLedger.load: $e');
    }
  }

  bool contains(String key) => _keys.contains(mediaKey(key));

  bool containsFile(MediaFile f) => _keys.contains(f.key);

  Future<void> add(String key) => addAll([key]);

  Future<void> addAll(Iterable<String> keys) async {
    await load();
    for (final k in keys) {
      final key = mediaKey(k);
      _keys.remove(key);
      _keys.add(key);
    }
    while (_keys.length > limit) {
      _keys.remove(_keys.first);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, _keys.toList(growable: false));
    } catch (e) {
      debugPrint('SavedMediaLedger.add: $e');
    }
  }

  /// Файлы, которых ещё нет в галерее.
  List<MediaFile> pending(Iterable<MediaFile> files) =>
      [for (final f in files) if (!containsFile(f)) f];

  int countSaved(Iterable<MediaFile> files) =>
      files.where(containsFile).length;
}
