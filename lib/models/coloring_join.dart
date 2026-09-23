import 'dart:convert';

/// Начатый лист раскраски: то, что про него известно из `canvas_meta`.
///
/// Зачем это вообще нужно. Раньше каждое «Новый холст → Раскраска» заводило
/// свой лист, и пара, выбрав одну и ту же картинку почти одновременно, красила
/// два разных листа: у каждого своя половина закрашена, вторая пустая. Живой
/// случай 13.09.2026 — пара rc3eb70972c9644, одиннадцать листов «Кафе», и ни на
/// одном нет штрихов от обоих. Теперь перед созданием листа приложение ищет
/// уже начатый ([coloringSheetToJoin]) и предлагает открыть его.
class ColoringSheet {
  const ColoringSheet({
    required this.canvasId,
    required this.pictureId,
    required this.lastActivity,
    this.done = const {},
  });

  final String canvasId;

  /// id картинки (`coloring_id`).
  final String pictureId;

  /// Когда на листе что-то происходило в последний раз: заведение раскраски
  /// или нажатие «Готово». Штрихи это время не двигают.
  final DateTime lastActivity;

  /// Кто уже нажал «Готово»: uid → true.
  final Map<String, bool> done;

  /// Строка `canvas_meta` → лист. null, если раскраски на холсте нет.
  ///
  /// `coloring_done` hotpath отдаёт картой, но старые пути отдавали его
  /// строкой JSON — читаем оба вида. Время берём из `updated_at`, а если его
  /// нет — из id холста (`canvas_<мс>`).
  static ColoringSheet? fromMetaRow(Map<String, dynamic> row) {
    final canvasId = (row['canvas_id'] ?? '').toString().trim();
    final pictureId = (row['coloring_id'] ?? '').toString().trim();
    if (canvasId.isEmpty || pictureId.isEmpty) return null;

    final at = DateTime.tryParse((row['updated_at'] ?? '').toString()) ??
        _timeFromCanvasId(canvasId);
    if (at == null) return null;

    return ColoringSheet(
      canvasId: canvasId,
      pictureId: pictureId,
      lastActivity: at,
      done: _readDone(row['coloring_done']),
    );
  }

  static DateTime? _timeFromCanvasId(String canvasId) {
    final ms = int.tryParse(canvasId.replaceFirst('canvas_', ''));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Map<String, bool> _readDone(dynamic raw) {
    dynamic v = raw;
    if (v is String && v.trim().isNotEmpty) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        v = null;
      }
    }
    if (v is! Map) return const {};
    return {for (final e in v.entries) e.key.toString(): e.value == true};
  }
}

/// Сколько начатый лист ждёт второго. Пара садится красить вечером; кто-то
/// доходит до листа на следующий день. Старше суток — скорее брошенный лист,
/// и звать в него при каждом выборе картинки было бы навязчиво: в «Моих
/// рисунках» он всё равно лежит.
const Duration coloringJoinWindow = Duration(hours: 24);

/// В какой уже начатый лист вести человека, выбравшего картинку [pictureId].
///
/// Подходит лист той же картинки, который:
/// - ещё лежит в каталоге пары ([listed]) — `canvas_meta` после удаления
///   холста остаётся, а в галерее такого листа уже нет;
/// - не закончен: «Готово» нажали не все из [members] (один нажал — вторая
///   половина ещё ждёт, это самый нужный случай);
/// - тронут не раньше [window] назад.
///
/// Кто лист завёл, не важно: свой недокрашенный лист тоже лучше продолжить,
/// чем плодить ещё один. Из нескольких берём самый свежий. null — заводим
/// новый лист, как раньше.
ColoringSheet? coloringSheetToJoin(
  Iterable<ColoringSheet> sheets, {
  required String pictureId,
  required List<String> members,
  required Set<String> listed,
  required DateTime now,
  Duration window = coloringJoinWindow,
}) {
  final pair = members.where((m) => m.isNotEmpty).toList();
  final since = now.subtract(window);

  ColoringSheet? best;
  for (final s in sheets) {
    if (s.pictureId != pictureId) continue;
    if (!listed.contains(s.canvasId)) continue;
    if (s.lastActivity.isBefore(since)) continue;
    final finished = pair.isNotEmpty && pair.every((m) => s.done[m] == true);
    if (finished) continue;
    if (best == null || s.lastActivity.isAfter(best.lastActivity)) best = s;
  }
  return best;
}
