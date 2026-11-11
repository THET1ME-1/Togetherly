import 'package:pocketbase/pocketbase.dart';

/// Записи виджетов пары на один фоновый проход.
///
/// Проход обновляет несколько виджетов подряд, и всем нужны одни и те же
/// записи `widget_data`. Пока каждая часть ходила на сервер сама, спящий
/// телефон слал около пяти одинаковых запросов за проход (TOG-90). Здесь
/// запрос один на пару: первый спросивший его шлёт, остальные ждут тот же
/// ответ. Сбой тоже общий, и повторов внутри прохода нет.
class WidgetRowsPass {
  WidgetRowsPass(this._load);

  final Future<List<RecordModel>> Function(String groupId) _load;
  final Map<String, Future<List<RecordModel>>> _asked = {};

  /// Записи обоих участников пары.
  Future<List<RecordModel>> rows(String groupId) =>
      _asked[groupId] ??= _load(groupId);

  /// Запись одного участника; `null` — записи у него нет.
  Future<RecordModel?> rowOf(String groupId, String uid) async {
    final all = await rows(groupId);
    if (uid.isEmpty) return null;
    for (final record in all) {
      if (record.data['user_uid'] == uid) return record;
    }
    return null;
  }
}
