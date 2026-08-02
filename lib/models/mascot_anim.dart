import 'dart:ui' as ui;

import 'level.dart';
import 'mascot_sleep.dart';

/// Что маскот делает прямо сейчас.
///
/// Первые пять состояний завязаны на серию, остальные — на руки: маскота на
/// главной таскают пальцем и меняют ему размер.
enum MascotAnimState {
  live,
  grow,
  freeze,
  sad,
  happy,
  grab,
  drag,
  drop,
  resize;

  /// Разовые: проигрываются один раз и возвращают маскота к обычной жизни.
  bool get oneShot =>
      this == MascotAnimState.grow ||
      this == MascotAnimState.happy ||
      this == MascotAnimState.drop;
}

/// Анимированный пиксельный маскот из каталога.
///
/// Вся анимация лежит одной картинкой: строки — состояния, столбцы — кадры.
/// Приложение не знает про конкретных персонажей и рисует их по манифесту,
/// поэтому новый маскот появляется у людей БЕЗ обновления — достаточно
/// положить запись в `catalog_items`.
class MascotAnim {
  const MascotAnim({
    required this.id,
    required this.nameRu,
    required this.nameEn,
    required this.sheetUrl,
    required this.frame,
    required this.cols,
    required this.fps,
    required this.rows,
    this.storyRu = '',
    this.levels = 3,
    this.levelOffsets = const {},
    this.extraIdles = const [],
    this.nightIdle = '',
    this.seasonIdles = const {},
    this.unlock = const Unlock.free(),
  });

  final String id;
  final String nameRu;
  final String nameEn;

  /// Атлас: строки — состояния из [rows], столбцы — кадры.
  final String sheetUrl;

  /// Сторона одного кадра в пикселях.
  final int frame;

  /// Сколько кадров в строке.
  final int cols;

  final int fps;

  /// Порядок строк атласа. Приходит из манифеста и НЕ выводится из enum:
  /// у выпущенных сборок порядок уже зашит в скачанный манифест, менять его
  /// задним числом нельзя.
  final List<String> rows;

  final String storyRu;

  /// Сколько ступеней роста у персонажа.
  final int levels;

  /// С какой строки атласа начинается блок ступени.
  ///
  /// Третья ступень лежит в нулевом блоке ради совместимости: сборки, вышедшие
  /// до появления ступеней, читают строку как `rowOf(state)` и попадают в него.
  /// Пустая карта — атлас старого образца, в нём ступеней нет вовсе.
  final Map<int, int> levelOffsets;

  /// Сцены, которые персонаж разыгрывает сам вместо обычного покоя: чистит
  /// перья, потягивается, зевает, поворачивается к вам спиной. Есть только у
  /// тех, кому их нарисовали, — остальные просто живут петлёй.
  final List<String> extraIdles;

  /// Сцена на ночь. Пусто — персонаж ночью живёт как днём.
  final String nightIdle;

  /// Облик по месяцам: {номер месяца: имя строки}. Так Сезонник переодевается
  /// сам — зимой снеговик, летом с арбузом, и это видно без обновления.
  final Map<int, String> seasonIdles;

  final Unlock unlock;

  /// Есть ли у маскота такая анимация. Каталог может отдать персонажа без
  /// редких состояний — тогда клиент падает на «живёт».
  bool has(MascotAnimState state) => rows.contains(state.name);

  /// Спит ли персонаж ночью или, наоборот, оживает.
  ///
  /// Считается по имени ночной строки: у спящих она `sleep`, у ночных своя
  /// (Мигун в эти часы как раз разгорается). Отдельного поля в манифесте нет
  /// намеренно — иначе пришлось бы перевыпускать все атласы ради подписи.
  bool get sleepsAtNight => nightIdle == 'sleep';

  int rowOf(MascotAnimState state) {
    final i = rows.indexOf(state.name);
    return i < 0 ? 0 : i;
  }

  /// Есть ли в атласе ступени роста.
  bool get hasLevels => levelOffsets.isNotEmpty;

  /// Прямоугольник кадра в атласе.
  ///
  /// [level] — ступень роста 1..[levels]. Незнакомая ступень и атлас без
  /// ступеней падают на нулевой блок: там лежит взрослый маскот, и это лучше
  /// пустоты.
  ui.Rect rect(MascotAnimState state, int index, {int level = 3}) =>
      rectRow(state.name, index, level: level);

  /// Кадр по ИМЕНИ строки. Своих сцен нет в перечислении состояний — они
  /// приходят из манифеста, и приложение про них ничего не знает заранее.
  ui.Rect rectRow(String row, int index, {int level = 3}) {
    final col = cols <= 0 ? 0 : index % cols;
    final offset = levelOffsets[level.clamp(1, levels)] ?? 0;
    var r = rows.indexOf(row);
    if (r < 0) r = rows.indexOf(MascotAnimState.live.name);
    if (r < 0) r = 0;
    return ui.Rect.fromLTWH(
      (col * frame).toDouble(),
      ((offset + r) * frame).toDouble(),
      frame.toDouble(),
      frame.toDouble(),
    );
  }

  /// Облик на сегодня. Пусто — у персонажа нет сезонных нарядов.
  String seasonRow(DateTime now) => seasonIdles[now.month] ?? '';

  /// Какую строку атласа крутить в покое прямо сейчас.
  ///
  /// Порядок старшинства: ночь важнее всего — она про время суток и держится,
  /// пока идёт окно; дальше своя сцена, которую персонаж затеял на этом круге;
  /// дальше сезонный наряд, потому что зимой снеговик — это обычный вид
  /// Сезонника, а не редкий выход.
  ///
  /// [sleep] задаёт человек в настройках, у каждого персонажа своё окно.
  String idleRow(DateTime now, SleepWindow sleep, {String scene = ''}) {
    if (nightIdle.isNotEmpty && sleep.contains(now)) return nightIdle;
    if (scene.isNotEmpty) return scene;
    final season = seasonRow(now);
    return season.isEmpty ? MascotAnimState.live.name : season;
  }

  /// Ступень роста по длине серии.
  ///
  /// Пороги подобраны так, чтобы рост был виден, но не обесценивался: первая
  /// неделя — малыш, месяц — подросток, дальше взрослый. Ровно на пороге
  /// маскот и подрастает, о чём сообщает анимация `grow`.
  static int levelForStreak(int streakDays) {
    if (streakDays >= 30) return 3;
    if (streakDays >= 7) return 2;
    return 1;
  }

  static MascotAnim? fromCatalog(
    Map<String, dynamic> row, {
    required Unlock unlock,
  }) {
    final id = row['id'] as String?;
    final data = (row['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sheet = data['sheet'] as String? ?? data['url'] as String?;
    if (id == null || id.isEmpty || sheet == null || sheet.isEmpty) return null;

    final rows = <String>[
      for (final r in (data['rows'] as List? ?? const [])) r.toString(),
    ];
    if (rows.isEmpty) return null;

    final frame = (data['frame'] as num?)?.toInt() ?? 48;
    final cols = (data['cols'] as num?)?.toInt() ?? 12;
    if (frame <= 0 || cols <= 0) return null;

    final offsets = <int, int>{};
    final rawOffsets = data['level_offsets'];
    if (rawOffsets is Map) {
      rawOffsets.forEach((k, v) {
        final lv = int.tryParse(k.toString());
        final off = (v as num?)?.toInt();
        if (lv != null && off != null) offsets[lv] = off;
      });
    }

    return MascotAnim(
      id: id,
      nameRu: row['name_ru'] as String? ?? id,
      nameEn: row['name_en'] as String? ?? id,
      sheetUrl: sheet,
      frame: frame,
      cols: cols,
      fps: (data['fps'] as num?)?.toInt() ?? 10,
      rows: List.unmodifiable(rows),
      storyRu: data['story_ru'] as String? ?? '',
      levels: (data['levels'] as num?)?.toInt() ?? 3,
      levelOffsets: Map.unmodifiable(offsets),
      extraIdles: List.unmodifiable([
        for (final e in (data['extra_idles'] as List? ?? const []))
          if (rows.contains(e.toString())) e.toString(),
      ]),
      nightIdle: rows.contains(data['night_idle']) ? data['night_idle'] as String : '',
      seasonIdles: Map.unmodifiable(<int, String>{
        for (final e in ((data['season_idles'] as Map?) ?? const {}).entries)
          if (int.tryParse(e.key.toString()) != null &&
              rows.contains(e.value.toString()))
            int.parse(e.key.toString()): e.value.toString(),
      }),
      unlock: unlock,
    );
  }
}
