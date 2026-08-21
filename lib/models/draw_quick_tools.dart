/// Что стоит в панели быстрого доступа холста и в каком порядке.
///
/// Раньше состав был зашит намертво: шесть кнопок из макета, всё прочее — в
/// меню «⋯». Ладонь и очистка нужны чаще, чем «удалить фото», поэтому набор
/// собирает сам человек, в настройках.
enum DrawQuickTool {
  brush,
  eraser,
  fill,
  shapes,
  layers,
  image,
  palm,
  select,
  background,
  clear,
  replay,
}

/// Набор по умолчанию: шесть кнопок из макета плюс ладонь и очистка — к ним
/// рука тянется чаще всего, а в меню «⋯» их приходилось искать.
const List<DrawQuickTool> kDefaultQuickTools = [
  DrawQuickTool.brush,
  DrawQuickTool.eraser,
  DrawQuickTool.fill,
  DrawQuickTool.shapes,
  DrawQuickTool.layers,
  DrawQuickTool.image,
  DrawQuickTool.palm,
  DrawQuickTool.clear,
];

/// Больше двух рядов панель не потянет: холст останется щелью.
const int kMaxQuickTools = 12;

/// Разбор настройки. Она переживает обновления приложения, поэтому незнакомые
/// имена пропускаются молча, а не роняют весь набор.
List<DrawQuickTool> parseQuickTools(String? raw) {
  if (raw == null || raw.trim().isEmpty) return kDefaultQuickTools;
  final out = <DrawQuickTool>[];
  for (final name in raw.split(',')) {
    final tool = DrawQuickTool.values
        .where((t) => t.name == name.trim())
        .firstOrNull;
    if (tool == null || out.contains(tool)) continue;
    out.add(tool);
    if (out.length >= kMaxQuickTools) break;
  }
  if (out.isEmpty) return kDefaultQuickTools;
  // Без кисти холст превращается в просмотрщик: рисовать нечем, и вернуть её
  // человек сможет только из настроек. Держим её первой.
  if (!out.contains(DrawQuickTool.brush)) {
    out.insert(0, DrawQuickTool.brush);
    if (out.length > kMaxQuickTools) out.removeLast();
  }
  return out;
}

String encodeQuickTools(List<DrawQuickTool> tools) =>
    tools.map((t) => t.name).join(',');

/// Сколько рядов займут кнопки. Ряд не резиновый: на 320 точках шесть кнопок
/// уже впритык, седьмая ушла бы за край.
int quickToolRows(int count, {required int perRow}) =>
    count <= 0 ? 0 : ((count - 1) ~/ perRow) + 1;
