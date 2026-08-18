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
      default:
        row[key] = value;
    }
  }
  return row;
}
