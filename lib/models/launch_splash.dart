import 'dart:ui';

/// Заставка при запуске: запись каталога вида `splash`, id `splash_<ключ>`.
///
/// Просьба владельца 19.10.2026: рисованная заставка на секунду-две под
/// праздник, выбор в «Оформлении», всё с сервера без обновления. Макет
/// https://claude.ai/artifact/JrCeo8VPr7yeMYRxDC5B8o, первая — «Ключ».
///
/// Приложение сцен не знает. Сцену рисует мастерская
/// (`togetherly-badges-hand/splash_hw.js`), а `bake_splash.py` разбирает её
/// на неподвижные рисунки и позу каждого слоя через каждые [step] мс. Здесь
/// эти рисунки двигаются по позам, поэтому новая заставка — это новая запись
/// каталога, а не новая сборка.
class LaunchSplash {
  const LaunchSplash({
    required this.key,
    required this.ms,
    required this.step,
    required this.design,
    required this.night,
    required this.sprites,
    required this.layers,
    required this.window,
    required this.files,
    required this.names,
    required this.raw,
    this.from = '',
    this.until = '',
    this.sort = 500,
  });

  final String key;

  /// Сколько идёт заставка.
  final int ms;

  /// Шаг поз в траекториях.
  final int step;

  /// Экран, на котором сцена нарисована (мерило 360×780).
  final Size design;

  /// Ночь под рисунками: она закрывает приложение, пока окно не открылось.
  final Color night;

  final Map<String, SplashSprite> sprites;
  final List<SplashLayer> layers;
  final SplashWindow window;

  /// Имя файла без расширения → адрес (с сервера) или путь (на диске).
  final Map<String, String> files;

  final Map<String, String> names;

  /// Первый день (`ГГГГ-ММ-ДД`, пусто — с любого дня) и день, с которого
  /// заставки уже нет (пусто — без конца).
  final String from, until;

  final int sort;

  /// Описание как пришло: оно и ложится на диск рядом с рисунками.
  final Map<String, dynamic> raw;

  /// Кадр для выбора в «Оформлении».
  String? get stillUrl => files['still'];

  /// Все файлы, без которых заставку не сыграть, и кадр для выбора.
  Iterable<String> get fileNames sync* {
    final seen = <String>{};
    for (final sprite in sprites.values) {
      for (final frame in sprite.frames) {
        if (seen.add(frame)) yield frame;
      }
    }
    if (files.containsKey('still')) yield 'still';
  }

  String nameFor(String lang) => names[lang] ?? names['en'] ?? names['ru'] ?? key;

  /// Идёт ли заставка в этот день по часам человека.
  bool isOn(DateTime now) {
    final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (from.isNotEmpty && day.compareTo(from) < 0) return false;
    return until.isEmpty || day.compareTo(until) < 0;
  }

  Map<String, dynamic> toJson() => {...raw, 'files': files};

  /// Та же заставка, но файлы лежат на диске.
  LaunchSplash withFiles(Map<String, String> local) => LaunchSplash.fromJson({...raw, 'files': local})!;

  static LaunchSplash? fromCatalog(Map<String, dynamic> row) {
    if (row['kind'] != 'splash') return null;
    final data = row['data'];
    if (data is! Map) return null;
    return fromJson(data.cast<String, dynamic>());
  }

  static LaunchSplash? fromJson(Map<String, dynamic> d) {
    final key = '${d['key'] ?? ''}'.trim();
    final ms = _num(d['ms'])?.toInt() ?? 0;
    final step = _num(d['step'])?.toInt() ?? 0;
    if (key.isEmpty || ms <= 0 || step <= 0) return null;

    final files = <String, String>{};
    final rawFiles = d['files'];
    if (rawFiles is Map) {
      rawFiles.forEach((k, v) {
        if (v is String && v.isNotEmpty) files['$k'] = v;
      });
    }

    final sprites = <String, SplashSprite>{};
    final rawSprites = d['sprites'];
    if (rawSprites is! Map) return null;
    for (final entry in rawSprites.entries) {
      final sprite = SplashSprite.fromJson(entry.value);
      if (sprite == null) return null;
      // Рисунок без файла не нарисовать: такая запись не годится целиком.
      if (sprite.frames.any((f) => !files.containsKey(f))) return null;
      sprites['${entry.key}'] = sprite;
    }

    final layers = <SplashLayer>[];
    final rawLayers = d['layers'];
    if (rawLayers is! List || rawLayers.isEmpty) return null;
    for (final raw in rawLayers) {
      final layer = SplashLayer.fromJson(raw);
      if (layer == null || !sprites.containsKey(layer.sprite)) return null;
      layers.add(layer);
    }

    final window = SplashWindow.fromJson(d['window']);
    if (window == null) return null;

    final names = <String, String>{};
    final rawNames = d['name'];
    if (rawNames is Map) {
      rawNames.forEach((k, v) {
        if (v is String && v.isNotEmpty) names['$k'] = v;
      });
    }

    return LaunchSplash(
      key: key,
      ms: ms,
      step: step,
      design: Size(_num(d['w'])?.toDouble() ?? 360, _num(d['h'])?.toDouble() ?? 780),
      night: _color(d['night']) ?? const Color(0xFF1E1729),
      sprites: sprites,
      layers: layers,
      window: window,
      files: files,
      names: names,
      raw: Map<String, dynamic>.of(d)..remove('files'),
      from: _day(d['from']),
      until: _day(d['until']),
      sort: _num(d['sort'])?.toInt() ?? 500,
    );
  }

  static String _day(Object? v) {
    final s = '${v ?? ''}'.trim();
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ? s : '';
  }
}

/// Неподвижный рисунок: кадры дрожи и место картинки в его собственных
/// координатах (в единицах сцены).
class SplashSprite {
  const SplashSprite({required this.frames, required this.box});

  final List<String> frames;
  final Rect box;

  static SplashSprite? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final frames = raw['frames'];
    final box = raw['box'];
    if (frames is! List || frames.isEmpty || box is! List || box.length != 4) return null;
    final names = [for (final f in frames) if (f is String && f.isNotEmpty) f];
    final nums = [for (final v in box) _num(v)?.toDouble()];
    if (names.length != frames.length || nums.contains(null)) return null;
    if (nums[2]! <= 0 || nums[3]! <= 0) return null;
    return SplashSprite(frames: names, box: Rect.fromLTWH(nums[0]!, nums[1]!, nums[2]!, nums[3]!));
  }
}

/// Слой сцены. [fill] — рисунок растянут на весь экран (дверь), [under] —
/// слой лежит в ночи, и окно его прорезает; остальные идут поверх окна.
class SplashLayer {
  const SplashLayer({required this.sprite, this.fill = false, this.under = false, this.track = const []});

  final String sprite;
  final bool fill;
  final bool under;
  final List<SplashPose> track;

  static SplashLayer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final sprite = '${raw['sprite'] ?? ''}';
    if (sprite.isEmpty) return null;
    final fill = raw['fill'] == true;
    final track = _track(raw['track']);
    if (track == null || (!fill && track.isEmpty)) return null;
    return SplashLayer(sprite: sprite, fill: fill, under: raw['under'] == true, track: track);
  }
}

/// Окно в ночи: форма сердца, рамка вокруг него (белая и тушью, толщина не
/// меняется с масштабом) и где оно на каждом шаге. Масштаб 0 — окна нет.
class SplashWindow {
  const SplashWindow({
    required this.path,
    required this.track,
    this.frameWidth = 12,
    this.inkWidth = 4,
    this.ink = const Color(0xFF2A2D30),
  });

  final Path path;
  final List<SplashPose> track;
  final double frameWidth, inkWidth;
  final Color ink;

  static SplashWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = parseSplashPath('${raw['path'] ?? ''}');
    final track = _track(raw['track']);
    if (path == null || track == null || track.isEmpty) return null;
    final frame = raw['frame'];
    double width(int i, double def) => frame is List && frame.length > i ? _num(frame[i])?.toDouble() ?? def : def;
    return SplashWindow(
      path: path,
      track: track,
      frameWidth: width(0, 12),
      inkWidth: width(1, 4),
      ink: _color(raw['ink']) ?? const Color(0xFF2A2D30),
    );
  }
}

/// Поза слоя: где его начало координат, масштаб, поворот в градусах,
/// прозрачность и кадр дрожи.
class SplashPose {
  const SplashPose(this.x, this.y, this.scale, [this.rotation = 0, this.opacity = 1, this.frame = 0]);

  final double x, y, scale, rotation, opacity;
  final int frame;
}

/// Поза на момент [ms]: между соседними шагами по прямой, кадр дрожи — от
/// нижнего шага. До начала — первый шаг, после конца — последний.
SplashPose splashPoseAt(List<SplashPose> track, int step, double ms) {
  if (track.isEmpty) return const SplashPose(0, 0, 0, 0, 0);
  final at = ms / step;
  if (at <= 0) return track.first;
  final i = at.floor();
  if (i >= track.length - 1) return track.last;
  final a = track[i], b = track[i + 1];
  final t = at - i;
  double mix(double p, double q) => p + (q - p) * t;
  return SplashPose(
    mix(a.x, b.x),
    mix(a.y, b.y),
    mix(a.scale, b.scale),
    mix(a.rotation, b.rotation),
    mix(a.opacity, b.opacity),
    a.frame,
  );
}

/// Путь из мастерской: команды `M`, `L`, `C`, `Q`, `Z` с абсолютными
/// координатами (так пишет `cr()` в badges.js). Незнакомое — null.
Path? parseSplashPath(String d) {
  final tokens = RegExp(r'[MLCQZmlcqz]|-?\d*\.?\d+(?:[eE][-+]?\d+)?').allMatches(d).map((m) => m[0]!).toList();
  if (tokens.isEmpty || tokens.first != 'M') return null;
  // В пути не должно быть ничего, кроме команд, чисел и разделителей.
  if (d.replaceAll(RegExp(r'[MLCQZ\d.,\s\-eE+]'), '').isNotEmpty) return null;
  final path = Path();
  var i = 0;
  var command = '';
  var closed = false;
  List<double>? take(int n) {
    if (i + n > tokens.length) return null;
    final out = <double>[];
    for (var k = 0; k < n; k++) {
      final v = double.tryParse(tokens[i + k]);
      if (v == null) return null;
      out.add(v);
    }
    i += n;
    return out;
  }

  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[A-Za-z]$').hasMatch(t)) {
      command = t;
      i++;
      if (command == 'Z') {
        path.close();
        closed = true;
        continue;
      }
    }
    switch (command) {
      case 'M':
        final p = take(2);
        if (p == null) return null;
        path.moveTo(p[0], p[1]);
        command = 'L';
      case 'L':
        final p = take(2);
        if (p == null) return null;
        path.lineTo(p[0], p[1]);
      case 'C':
        final p = take(6);
        if (p == null) return null;
        path.cubicTo(p[0], p[1], p[2], p[3], p[4], p[5]);
      case 'Q':
        final p = take(4);
        if (p == null) return null;
        path.quadraticBezierTo(p[0], p[1], p[2], p[3]);
      default:
        return null;
    }
  }
  return closed ? path : null;
}

List<SplashPose>? _track(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) return null;
  final out = <SplashPose>[];
  for (final row in raw) {
    if (row is! List || row.length < 3) return null;
    final v = [for (final x in row) _num(x)?.toDouble()];
    if (v.contains(null)) return null;
    out.add(SplashPose(
      v[0]!,
      v[1]!,
      v[2]!,
      v.length > 3 ? v[3]! : 0,
      v.length > 4 ? v[4]!.clamp(0.0, 1.0) : 1,
      v.length > 5 ? v[5]!.toInt() : 0,
    ));
  }
  return out;
}

num? _num(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);

Color? _color(Object? v) {
  final s = '${v ?? ''}'.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(0xFF000000 | int.parse(s, radix: 16));
}
