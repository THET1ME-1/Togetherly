import 'dart:convert';

/// Когда персонаж уходит в ночную сцену.
///
/// Ночь до этого была зашита намертво — с 23:00 до 07:00 у всех. Теперь окно
/// своё у каждого персонажа: у кого-то часы бьют до полуночи, а Мигун в эти
/// часы наоборот разгорается, он ночной.
class SleepWindow {
  const SleepWindow({required this.from, required this.to, this.enabled = true});

  /// Прежнее поведение: с одиннадцати вечера до семи утра. Достаётся всем, кто
  /// ничего не настраивал.
  static const SleepWindow standard = SleepWindow(from: 23 * 60, to: 7 * 60);

  /// Начало и конец в минутах от полуночи, 0…1439.
  final int from;
  final int to;

  /// Выключенная ночь: персонаж живёт одинаково круглые сутки.
  final bool enabled;

  int get fromHour => from ~/ 60;
  int get fromMinute => from % 60;
  int get toHour => to ~/ 60;
  int get toMinute => to % 60;

  /// Идёт ли ночная сцена в этот момент.
  ///
  /// Начало включено, конец нет: в 07:00 персонаж уже проснулся. Окно нулевой
  /// длины не значит «круглые сутки» — человек просто свёл обе стрелки в одну
  /// точку, и понимать это как вечный сон было бы издевательством.
  bool contains(DateTime now) {
    if (!enabled || from == to) return false;
    final m = now.hour * 60 + now.minute;
    return from < to ? m >= from && m < to : m >= from || m < to;
  }

  SleepWindow copyWith({int? from, int? to, bool? enabled}) => SleepWindow(
        from: from ?? this.from,
        to: to ?? this.to,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is SleepWindow &&
      other.from == from &&
      other.to == to &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(from, to, enabled);

  @override
  String toString() =>
      'SleepWindow($from→$to${enabled ? '' : ', выключено'})';
}

/// Расписание сна всех персонажей: `id маскота → окно`.
///
/// Живёт в поле `users.mascot_sleep`, поэтому разбор обязан выдерживать что
/// угодно: старые записи поля не имеют вовсе, а PocketBase отдаёт json то
/// картой, то строкой — смотря пришло оно по сети или поднялось из кэша.
class MascotSleep {
  const MascotSleep._();

  static const int _minutesInDay = 24 * 60;

  static Map<String, SleepWindow> parse(Object? raw) {
    final source = raw is String ? _decodeString(raw) : raw;
    if (source is! Map) return const {};

    final out = <String, SleepWindow>{};
    source.forEach((key, value) {
      final id = key.toString();
      if (id.isEmpty || value is! Map) return;
      final from = _minutes(value['from']);
      final to = _minutes(value['to']);
      if (from == null || to == null) return;
      out[id] = SleepWindow(
        from: from,
        to: to,
        enabled: value['enabled'] is bool ? value['enabled'] as bool : true,
      );
    });
    return out;
  }

  /// Окно персонажа. Ничего не настроено — прежние 23:00–07:00.
  static SleepWindow of(Map<String, SleepWindow> all, String mascotId) =>
      all[mascotId] ?? SleepWindow.standard;

  /// Что отправить на сервер.
  ///
  /// Персонажи с прежним окном выпадают: хранить умолчание значит раздувать
  /// поле записями, которые ничего не решают.
  static Map<String, dynamic> encode(Map<String, SleepWindow> all) {
    final out = <String, dynamic>{};
    all.forEach((id, w) {
      if (w == SleepWindow.standard) return;
      out[id] = {
        'from': w.from,
        'to': w.to,
        if (!w.enabled) 'enabled': false,
      };
    });
    return out;
  }

  static Object? _decodeString(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static int? _minutes(Object? value) {
    final n = value is num ? value.toInt() : null;
    if (n == null || n < 0 || n >= _minutesInDay) return null;
    return n;
  }
}
