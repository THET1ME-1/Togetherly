import 'dart:ui';

/// Виджет «Чем заняты»: чем человек сейчас занят и в какой цвет покрашена его
/// половина.
///
/// Всё живёт в его записи `widget_data`, в поле json `data`, рядом с заметкой
/// на двоих: ключ `doing` — занятие, ключ `room` — цвет стены. Схему сервера
/// это не трогает, а правка записи сама будит телефон партнёра.

/// Занятия, у которых есть нарисованная сцена (`act_<id>` в каталоге).
const List<String> kDoingIds = [
  'study',
  'sleep',
  'rest',
  'shower',
  'toilet',
  'work',
  'eat',
  'road',
  'gym',
  'game',
  'cook',
  'walk',
  'movie',
  'clean',
  'shop',
  'friends',
  'sick',
  'busy',
];

/// Своё слово вместо готового занятия: Ту в покое, слово в плашке.
const String kDoingOwn = 'own';

/// Длина своего слова: больше в плашку виджета не помещается.
const int kDoingTextMax = 24;

/// Через сколько занятие гаснет само. Иначе «в душе» висело бы полночи.
const Duration kDoingFades = Duration(hours: 3);

class Doing {
  /// Что из [kDoingIds], [kDoingOwn] или пусто — занятия нет.
  final String id;

  /// Своё слово. Пусто у готовых занятий.
  final String text;

  /// Когда человек это поставил, миллисекунды эпохи.
  final int atMs;

  const Doing._(this.id, this.text, this.atMs);

  const Doing.none() : this._('', '', 0);

  factory Doing.of(String id, DateTime at) {
    if (!kDoingIds.contains(id)) return const Doing.none();
    return Doing._(id, '', at.millisecondsSinceEpoch);
  }

  factory Doing.own(String word, DateTime at) {
    var text = word.trim();
    if (text.length > kDoingTextMax) text = text.substring(0, kDoingTextMax).trim();
    if (text.isEmpty) return const Doing.none();
    return Doing._(kDoingOwn, text, at.millisecondsSinceEpoch);
  }

  /// Читает занятие из поля `data` записи виджета. Чужая сборка может
  /// прислать что угодно, поэтому всё непонятное — «занятия нет».
  factory Doing.fromData(Object? data) {
    if (data is! Map) return const Doing.none();
    final raw = data['doing'];
    if (raw is! Map) return const Doing.none();

    final id = raw['id'];
    if (id is! String) return const Doing.none();
    final at = DateTime.fromMillisecondsSinceEpoch((raw['at'] as num?)?.toInt() ?? 0);

    if (id == kDoingOwn) return Doing.own((raw['text'] ?? '').toString(), at);
    return Doing.of(id, at);
  }

  bool get isNone => id.isEmpty;
  bool get isOwn => id == kDoingOwn;

  /// Ключ сцены в каталоге. У своего слова и у покоя сцены нет.
  String? get artKey => isNone || isOwn ? null : 'act_$id';

  /// Что показывать в момент [now]: само занятие или уже покой.
  Doing shownAt(DateTime now) {
    if (isNone) return this;
    final age = now.millisecondsSinceEpoch - atMs;
    return age >= kDoingFades.inMilliseconds ? const Doing.none() : this;
  }

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'at': atMs};
}

/// Поле `data` с новым занятием. Остальные ключи (заметка, цвет) на месте:
/// сервер перезаписывает json целиком, и потерять соседа легко.
Map<String, dynamic> withDoing(Map<dynamic, dynamic> data, Doing doing) {
  final out = Map<String, dynamic>.from(data);
  if (doing.isNone) {
    out.remove('doing');
  } else {
    out['doing'] = doing.toJson();
  }
  return out;
}

/// Поле `data` с новым цветом комнатки. `null` — вернуть цвет темы.
Map<String, dynamic> withRoom(Map<dynamic, dynamic> data, Color? wall) {
  final out = Map<String, dynamic>.from(data);
  if (wall == null) {
    out.remove('room');
  } else {
    out['room'] = roomHex(wall);
  }
  return out;
}

final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Цвет стены из поля `data`. Нет ключа или он не `#rrggbb` — цвет темы.
Color? roomColorOf(Object? data) {
  if (data is! Map) return null;
  final raw = data['room'];
  if (raw is! String || !_hexColor.hasMatch(raw)) return null;
  return Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
}

String roomHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Цвет пола и горошка по цвету стены. Человек выбирает только стену.
///
/// У белой стены пол чуть темнее, иначе его не видно; у светлой — светлее;
/// у тёмной тоже светлее, но на малую долю, чтобы комнатка осталась тёмной.
Color roomFloor(Color wall) {
  final brightness = wall.computeLuminance();
  if (brightness > 0.88) return _mix(wall, const Color(0xFF8F7F86), 0.14);
  if (brightness > 0.4) return _mix(wall, const Color(0xFFFFFFFF), 0.55);
  return _mix(wall, const Color(0xFFFFFFFF), 0.16);
}

Color _mix(Color from, Color to, double share) {
  int channel(int a, int b) => (a + (b - a) * share).round();
  final a = from.toARGB32(), b = to.toARGB32();
  return Color.fromARGB(
    255,
    channel((a >> 16) & 0xFF, (b >> 16) & 0xFF),
    channel((a >> 8) & 0xFF, (b >> 8) & 0xFF),
    channel(a & 0xFF, b & 0xFF),
  );
}

/// Отпечаток занятия и цвета в записи виджета. Запись партнёра меняется по
/// десятку поводов (настроение, фото, музыка), а половину «Чем заняты»
/// пересобирать нужно только когда сменилось одно из этих двух.
String doingSignatureOf(Map<String, dynamic> record) {
  final data = record['data'];
  if (data is! Map) return '';
  final doing = data['doing'];
  final what = doing is Map ? '${doing['id'] ?? ''}|${doing['text'] ?? ''}|${doing['at'] ?? ''}' : '';
  return '$what|${data['room'] ?? ''}';
}

/// «19:40» — с какого времени человек этим занят, по часам телефона.
String doingTime(int atMs) {
  if (atMs <= 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(atMs);
  return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}
