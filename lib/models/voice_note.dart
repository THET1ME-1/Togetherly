import 'dart:math' as math;

/// Огибающая громкости голосового сообщения.
///
/// Сорок замеров, каждый — цифра `0`–`9`. Строка ложится в text-поле
/// `chat_messages.voice_peaks` и весит сорок байт, поэтому партнёр рисует ту же
/// волну, что видел отправитель, ничего не скачивая: файл тянется только при
/// нажатии «слушать».
class VoicePeaks {
  /// Сколько столбиков в волне. Больше сорока на ширине пузыря сливается в
  /// сплошную заливку, меньше — читается как гистограмма, а не как речь.
  static const int count = 40;

  /// Нижняя граница столбика. Ноль рисовал бы разрыв полосы посреди паузы,
  /// поэтому тишина — короткая засечка, а не пустота.
  static const double floor = 0.12;

  static const String _digits = '0123456789';

  /// Замеры амплитуды (0..1 или дБ, приведённые вызывающим) → строка из 40 цифр.
  ///
  /// Нормализуем по самому громкому месту записи: без этого шёпот выглядел бы
  /// ровной ниткой, а крик — сплошной заливкой, хотя рисуем мы одно и то же —
  /// форму речи.
  static String encode(List<double> amplitudes) {
    if (amplitudes.isEmpty) {
      return _digits[_level(floor)] * count;
    }
    final buckets = _resample(amplitudes, count);
    final peak = buckets.reduce(math.max);
    // Тихая запись целиком (амплитуда почти нулевая) — это молчание, а не повод
    // растянуть шум микрофона на всю высоту.
    final scale = peak <= 0.02 ? 0.0 : 1 / peak;
    final sb = StringBuffer();
    for (final b in buckets) {
      final v = floor + (1 - floor) * (b * scale).clamp(0.0, 1.0);
      sb.write(_digits[_level(v)]);
    }
    return sb.toString();
  }

  /// Строка из записи → 40 значений 0..1 для отрисовки.
  ///
  /// Пустая строка и мусор дают ровную полосу: сообщение от старого клиента или
  /// повреждённое поле должно выглядеть как голосовое, а не как дыра в чате.
  static List<double> decode(String raw) {
    final clean = raw.split('').where((c) => _digits.contains(c)).toList();
    if (clean.length < count) {
      return List<double>.filled(count, 0.35);
    }
    final take = clean.length == count
        ? clean
        : _resampleStrings(clean, count);
    return take.map((c) => _digits.indexOf(c) / 9).toList();
  }

  static int _level(double v) => (v.clamp(0.0, 1.0) * 9).round();

  /// Сводит произвольное число замеров к [target] столбикам по среднему в окне.
  static List<double> _resample(List<double> src, int target) {
    if (src.length <= target) {
      // Замеров меньше, чем столбиков (короткая запись) — растягиваем, повторяя
      // соседа: ступеньки честнее, чем интерполяция несуществующего звука.
      return List<double>.generate(
          target, (i) => src[(i * src.length ~/ target).clamp(0, src.length - 1)]);
    }
    final out = <double>[];
    final step = src.length / target;
    for (var i = 0; i < target; i++) {
      final from = (i * step).floor();
      final to = math.min(src.length, ((i + 1) * step).ceil());
      var sum = 0.0;
      for (var j = from; j < to; j++) {
        sum += src[j];
      }
      out.add(sum / math.max(1, to - from));
    }
    return out;
  }

  static List<String> _resampleStrings(List<String> src, int target) =>
      List<String>.generate(
          target, (i) => src[(i * src.length ~/ target).clamp(0, src.length - 1)]);
}

/// Голосовое сообщение внутри записи чата: ссылка, длительность, волна.
class VoiceNote {
  /// `pb://media/<id>/<file>` у отправленного, локальный путь у ждущего очереди.
  final String url;
  final Duration duration;

  /// Значения 0..1 под столбики, всегда [VoicePeaks.count] штук.
  final List<double> peaks;

  const VoiceNote({
    required this.url,
    required this.duration,
    required this.peaks,
  });

  /// Собирает голосовое из полей записи. Нет ссылки — нет и голосового
  /// (обычное текстовое сообщение).
  static VoiceNote? fromFields({
    required String? url,
    required int? ms,
    required String? peaks,
  }) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    return VoiceNote(
      url: u,
      duration: Duration(milliseconds: math.max(0, ms ?? 0)),
      peaks: VoicePeaks.decode(peaks ?? ''),
    );
  }

  /// Запись ещё не уехала на сервер и лежит файлом на устройстве.
  bool get isLocalFile => !url.startsWith('pb://') && !url.startsWith('http');

  /// «0:07», «1:02» — так подписан каждый голосовой пузырь.
  static String formatDuration(Duration d) {
    final total = d.inSeconds;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
