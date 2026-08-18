/// Журнал отрисовки виджета, оставленный расширением в общем контейнере.
///
/// Виджет живёт отдельным процессом, и в Bugsink пишет приложение, а не он.
/// Поэтому расширение оставляет короткие записи, а приложение при запуске
/// забирает их и отправляет вместе со сводкой контейнера. Так становится видно
/// то, чего снаружи не разглядеть: на каком размере строился виджет, нашёлся ли
/// файл, сколько он весит, разжался ли и сколько памяти оставалось процессу.
///
/// Ради этого журнал и заведён 18.08.2026: квадрат 1×1 не показывал фотографию,
/// а средний и большой показывали ту же самую. Данные в контейнере при этом
/// лежали на месте, значит дело внутри расширения, куда нам не видно.
///
/// Формат строки — `время|размер|виджет|ключ=значение;ключ=значение`. Запись
/// без признака завершения означает, что расширение убили посередине: это и
/// есть подпись нехватки памяти.
library;

/// Ключ журнала в общем контейнере. Совпадает с `WidgetRenderLog.key` в
/// ios/TogetherlyWidget/SharedStore.swift — разъедутся, и журнал не доедет.
const String kWidgetRenderLogKey = 'widget_render_log';

/// Сколько последних записей несём в отчёт. Вся история незачем, важен хвост.
const int kWidgetRenderLogTail = 30;

List<Map<String, String>> parseWidgetRenderLog(String raw) {
  final out = <Map<String, String>>[];
  for (final line in raw.split('\n')) {
    final row = _parseLine(line.trim());
    if (row != null) out.add(row);
  }
  if (out.length <= kWidgetRenderLogTail) return out;
  return out.sublist(out.length - kWidgetRenderLogTail);
}

Map<String, String>? _parseLine(String line) {
  if (line.isEmpty) return null;
  final parts = line.split('|');
  if (parts.length < 3) return null;

  final row = <String, String>{
    'размер': parts[1],
    'виджет': parts[2],
  };
  if (parts.length < 4 || parts[3].isEmpty) return row;

  for (final pair in parts[3].split(';')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final key = pair.substring(0, eq);
    final value = pair.substring(eq + 1);
    switch (key) {
      case 'start':
        row['начал'] = value == '1' ? 'да' : 'нет';
      case 'path':
        row['файл'] = value == '1' ? 'есть' : 'путь пуст';
      case 'missing':
        row['файла нет на диске'] = value == '1' ? 'да' : 'нет';
      case 'bytes':
        final n = int.tryParse(value);
        if (n != null) row['вес'] = '${(n / 1024).round()} КБ';
      case 'decoded':
        row['разжато'] = value == '1' ? 'да' : 'нет';
      case 'px':
        row['пиксели'] = value;
      case 'mem':
        row['памяти оставалось'] = '$value МБ';
      case 'keys':
        row['ключей с данными'] = value;
      case 'stage':
        row['этап'] = value == 'snapshot' ? 'снимок' : 'таймлайн';
      case 'preview':
        row['галерея'] = value == '1' ? 'да' : 'нет';
      case 'reason':
        row['причина'] = value;
      default:
        row[key] = value;
    }
  }
  return row;
}

/// Короткий вердикт по журналу — уходит прямо в заголовок события Bugsink,
/// чтобы искать по названию, а не по времени.
String widgetRenderVerdict(List<Map<String, String>> rows) {
  if (rows.isEmpty) return 'журнал пуст';

  for (final row in rows) {
    final size = row['размер'] ?? '?';
    if (row['файла нет на диске'] == 'да') return '$size: файла нет на диске';
    if (row['разжато'] == 'нет') {
      final why = row['причина'];
      return why == null
          ? '$size не разжал картинку'
          : '$size не разжал картинку ($why)';
    }
  }

  // Начал и не закончил: расширение убили посередине. Это подпись нехватки
  // памяти — ей и место в заголовке.
  for (var i = 0; i < rows.length; i++) {
    if (rows[i]['начал'] != 'да') continue;
    final size = rows[i]['размер'];
    final finished = rows
        .skip(i + 1)
        .any((r) => r['размер'] == size && r.containsKey('разжато'));
    if (!finished) {
      final mem = rows[i]['памяти оставалось'];
      return mem == null
          ? '$size оборвался'
          : '$size оборвался (память $mem)';
    }
  }
  return 'ок';
}
