/// Договор с нативной стороной про виджет «Рисунок на столе».
///
/// Отдельным файлом и чистыми функциями, потому что состав ключей проверяется
/// тестом: натив читает их по строкам, и расхождение видно только на
/// устройстве — виджет просто остаётся пустым.
library;

/// Классы-провайдеры: размер в Android выбирается до установки, поэтому у
/// каждого свой приёмник, и будить надо все.
const List<String> kCanvasWidgetProviders = [
  'CanvasWidget2x2Provider',
  'CanvasWidget2x3Provider',
  'CanvasWidget4x4Provider',
];

/// Один холст в каталоге выбора.
class CanvasWidgetItem {
  final String id;
  final String name;

  /// Путь к PNG на диске. Пусто — холст ещё не нарисован.
  final String path;

  /// Когда его last трогали, миллисекунды.
  final int updatedMs;

  const CanvasWidgetItem({
    required this.id,
    required this.name,
    required this.path,
    required this.updatedMs,
  });

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'updated': updatedMs,
      };
}

/// Ключи, которые уезжают в `HomeWidgetPreferences`.
///
/// `canvas_<gid>_active` — холст по умолчанию: тот, который трогали последним.
/// Экземпляр виджета может выбрать свой (`widget_canvas_<widgetId>`), и тогда
/// натив берёт его; так человек ставит на стол хоть три разных рисунка.
Map<String, String> canvasWidgetKeys({
  required String groupId,
  required List<CanvasWidgetItem> items,
  required String activeId,
}) {
  final g = groupId.isEmpty ? 'solo' : groupId;
  final keys = <String, String>{
    'canvas_${g}_active': activeId,
    'canvas_${g}_count': '${items.length}',
    'canvas_latest_group': g,
  };

  // Каждый холст отдельным ключом, а не одним json: натив читает строку по
  // идентификатору и не разбирает разметку. Список для экрана выбора
  // собирается из `canvas_<gid>_list`.
  for (final item in items) {
    keys['canvas_${g}_${item.id}_path'] = item.path;
    keys['canvas_${g}_${item.id}_name'] = item.name;
  }
  keys['canvas_${g}_list'] = items.map((i) => i.id).join(',');
  return keys;
}
