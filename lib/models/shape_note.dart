import 'dart:math' as math;

/// Фигурка — короткое видео, обрезанное формой (сердце, звёздочка, ромбик…).
///
/// Живёт в тех же полях записи чата, что и голосовое, только своих: ссылка на
/// файл, длительность, имя формы, обложка и отметки-сердечки. Обложка нужна
/// затем же, зачем голосовому огибающая, — чтобы фигурка нарисовалась сразу и
/// не ждала, пока приедет видео.
class ShapeNote {
  /// `pb://media/<id>/<file>` у отправленной, путь на устройстве у той, что
  /// ещё стоит в очереди.
  final String url;

  final Duration duration;

  /// Имя формы (`heart`, `star`, …) — см. `widgets/chat/note_shapes.dart`.
  final String shapeId;

  /// Кадр из середины ролика. Пусто — покажем заливку темы.
  final String thumbUrl;

  /// Секунды, на которых смотрящий поставил сердечки.
  final List<double> hearts;

  const ShapeNote({
    required this.url,
    required this.duration,
    required this.shapeId,
    required this.thumbUrl,
    required this.hearts,
  });

  /// Сколько сердечек влезает в поле. Тридцать — это по одному на секунду
  /// самой длинной фигурки; дальше отметки перестают что-либо значить, а поле
  /// начинает расти без пользы.
  static const int maxHearts = 30;

  /// Собирает фигурку из полей записи. Нет ссылки — это не фигурка.
  static ShapeNote? fromFields({
    required String? url,
    required int? ms,
    required String? shape,
    required String? thumb,
    required String? hearts,
  }) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    return ShapeNote(
      url: u,
      duration: Duration(milliseconds: math.max(0, ms ?? 0)),
      shapeId: (shape ?? '').trim(),
      thumbUrl: (thumb ?? '').trim(),
      hearts: decodeHearts(hearts),
    );
  }

  /// Файл ещё на устройстве и ждёт очереди.
  bool get isLocalFile => !url.startsWith('pb://') && !url.startsWith('http');

  bool get hasThumb => thumbUrl.isNotEmpty;

  /// «0:07» — подпись под фигуркой.
  static String formatDuration(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// `"3.2,7.8"` → секунды. Мусор молча пропускаем: одна битая отметка не
  /// повод потерять остальные.
  static List<double> decodeHearts(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return const [];
    final out = <double>[];
    for (final part in s.split(',')) {
      final v = double.tryParse(part.trim());
      if (v != null && v.isFinite && v >= 0) out.add(v);
    }
    out.sort();
    return out.length <= maxHearts ? out : out.sublist(0, maxHearts);
  }

  /// Секунды → строка для поля. Округляем до десятых: точнее человек всё
  /// равно не тапнет, а поле короче втрое.
  static String encodeHearts(List<double> seconds) {
    final take = seconds.length <= maxHearts
        ? seconds
        : seconds.sublist(seconds.length - maxHearts);
    return take.map((s) => s.toStringAsFixed(1)).join(',');
  }
}
