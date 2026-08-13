import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'pocketbase_service.dart';

/// Развёрнутая статистика пары одним запросом.
///
/// Сервер считает всё агрегатами SQL и отдаёт готовые числа (`/api/couple/stats`).
/// Тянуть записи на клиент нельзя: у активной пары десятки тысяч сообщений, и
/// один график стоил бы мегабайтов трафика на каждом открытии экрана.
///
/// Ответ живёт в памяти пять минут: экран открывают подряд по нескольку раз,
/// а цифры за это время не меняются настолько, чтобы платить новым запросом.
class CoupleStatsService {
  CoupleStatsService._();

  static final Map<String, _Cached> _cache = {};
  static const _ttl = Duration(minutes: 5);

  static Future<CoupleStats?> load(String groupId, {bool force = false}) async {
    if (groupId.isEmpty) return null;

    final hit = _cache[groupId];
    if (!force && hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return hit.data;
    }

    final pb = PocketBaseService.instance.pb;
    final token = pb.authStore.token;
    if (token.isEmpty) return null;

    try {
      final res = await http.get(
        Uri.parse(
          '${PocketBaseService.baseUrl}/api/couple/stats?groupId=$groupId',
        ),
        headers: {'Authorization': token},
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        debugPrint('CoupleStatsService: HTTP ${res.statusCode}');
        return hit?.data;
      }
      final stats = CoupleStats.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      _cache[groupId] = _Cached(stats, DateTime.now());
      return stats;
    } catch (e) {
      debugPrint('CoupleStatsService.load failed: $e');
      // Отдаём прошлый ответ, если он был: устаревшие цифры полезнее пустого
      // экрана, а «обновить» пользователь нажмёт сам.
      return hit?.data;
    }
  }
}

class _Cached {
  const _Cached(this.data, this.at);
  final CoupleStats data;
  final DateTime at;
}

/// Разобранный ответ сервера. Всё поле-в-поле, без вычислений: считать здесь
/// значит разойтись с сервером при первой же правке SQL.
class CoupleStats {
  CoupleStats({
    required this.streak,
    required this.xp,
    required this.startDate,
    required this.anniversary,
    required this.members,
    required this.totals,
    required this.byMember,
    required this.timeline,
    required this.weekdayMessages,
    required this.weekdayMemories,
    required this.hourMessages,
    required this.moodDaily,
    required this.moodTop,
    required this.memoryTypes,
    required this.giftKinds,
    required this.watchKinds,
    required this.pace,
    required this.firstMemory,
  });

  final int streak;
  final int xp;
  final DateTime? startDate;
  final DateTime? anniversary;

  /// uid → имя. Порядок как в группе.
  final Map<String, String> members;

  /// Итоги за всё время: memories, messages, moods, missYou и прочее.
  final Map<String, int> totals;

  /// Метрика → (uid → сколько). Основа сравнений «я и партнёр».
  final Map<String, Map<String, int>> byMember;

  /// Ряд → месяцы «YYYY-MM» → сколько. Двенадцать месяцев назад.
  final Map<String, Map<String, int>> timeline;

  /// Индекс 0 — воскресенье, как отдаёт strftime('%w').
  final List<int> weekdayMessages;
  final List<int> weekdayMemories;
  final List<int> hourMessages;

  /// Отметки настроения за 90 дней: дата, автор, идентификатор настроения.
  final List<MoodPoint> moodDaily;

  /// Самые частые настроения каждого: id, автор, сколько раз.
  final List<MoodPoint> moodTop;

  final Map<String, int> memoryTypes;
  final Map<String, int> giftKinds;
  final Map<String, int> watchKinds;

  /// Темп последних недель — основа прогнозов.
  final Map<String, int> pace;
  final DateTime? firstMemory;

  int total(String key) => totals[key] ?? 0;

  int forMember(String metric, String uid) => byMember[metric]?[uid] ?? 0;

  static Map<String, int> _counts(dynamic list, String keyField) {
    final out = <String, int>{};
    if (list is! List) return out;
    for (final item in list) {
      if (item is! Map) continue;
      final k = '${item[keyField] ?? ''}';
      out[k] = (out[k] ?? 0) + ((item['c'] as num?)?.toInt() ?? 0);
    }
    return out;
  }

  static List<int> _slots(dynamic list, String keyField, int size) {
    final out = List<int>.filled(size, 0);
    if (list is! List) return out;
    for (final item in list) {
      if (item is! Map) continue;
      final i = (item[keyField] as num?)?.toInt() ?? -1;
      if (i < 0 || i >= size) continue;
      out[i] = (item['c'] as num?)?.toInt() ?? 0;
    }
    return out;
  }

  static DateTime? _date(dynamic raw) {
    final s = '${raw ?? ''}'.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  factory CoupleStats.fromJson(Map<String, dynamic> j) {
    final couple = (j['couple'] as Map?) ?? const {};
    final by = (j['byMember'] as Map?) ?? const {};
    final tl = (j['timeline'] as Map?) ?? const {};
    final rhythm = (j['rhythm'] as Map?) ?? const {};
    final mood = (j['mood'] as Map?) ?? const {};
    final breakdown = (j['breakdown'] as Map?) ?? const {};
    final pace = (j['pace'] as Map?) ?? const {};

    final members = <String, String>{};
    for (final m in (j['members'] as List? ?? const [])) {
      if (m is Map) members['${m['uid']}'] = '${m['name'] ?? ''}';
    }

    Map<String, int> byMetric(String key) {
      final out = <String, int>{};
      for (final item in (by[key] as List? ?? const [])) {
        if (item is Map) {
          out['${item['uid']}'] = (item['c'] as num?)?.toInt() ?? 0;
        }
      }
      return out;
    }

    Map<String, int> series(String key) => _counts(tl[key], 'm');

    return CoupleStats(
      streak: (couple['streak'] as num?)?.toInt() ?? 0,
      xp: (couple['xp'] as num?)?.toInt() ?? 0,
      startDate: _date(couple['start']),
      anniversary: _date(couple['anniversary']),
      members: members,
      totals: {
        for (final e in ((j['totals'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num?)?.toInt() ?? 0,
      },
      byMember: {
        'memories': byMetric('memories'),
        'messages': byMetric('messages'),
        'moods': byMetric('moods'),
        'missYou': byMetric('missYou'),
        'gifts': byMetric('gifts'),
      },
      timeline: {
        'memories': series('memories'),
        'messages': series('messages'),
        'moods': series('moods'),
      },
      weekdayMessages: _slots(rhythm['weekdayMessages'], 'd', 7),
      weekdayMemories: _slots(rhythm['weekdayMemories'], 'd', 7),
      // Сервер считает часы по UTC — `chat_messages.ts` абсолютный. Гистограмму
      // поворачиваем на пояс читателя, иначе у московской пары пик в 21:00
      // рисуется на 18:00.
      hourMessages: shiftHoursToLocal(
          _slots(rhythm['hourMessages'], 'h', 24), DateTime.now().timeZoneOffset),
      moodDaily: [
        for (final p in (mood['daily'] as List? ?? const []))
          if (p is Map) MoodPoint.fromJson(p),
      ],
      moodTop: [
        for (final p in (mood['top'] as List? ?? const []))
          if (p is Map) MoodPoint.fromJson(p),
      ],
      memoryTypes: _counts(breakdown['memoryTypes'], 'k'),
      giftKinds: _counts(breakdown['gifts'], 'k'),
      watchKinds: _counts(breakdown['watchKinds'], 'k'),
      pace: {
        for (final e in pace.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
      firstMemory: _date(pace['firstMemory']),
    );
  }
}

/// Отметка настроения: день, автор, идентификатор настроения и сколько раз.
class MoodPoint {
  const MoodPoint({
    required this.day,
    required this.uid,
    required this.moodId,
    required this.count,
  });

  final DateTime? day;
  final String uid;
  final String moodId;
  final int count;

  factory MoodPoint.fromJson(Map raw) => MoodPoint(
        day: DateTime.tryParse('${raw['d'] ?? ''}'),
        uid: '${raw['uid'] ?? ''}',
        moodId: '${raw['id'] ?? ''}',
        count: (raw['c'] as num?)?.toInt() ?? 0,
      );
}

/// Гистограмму часов, посчитанную сервером в UTC, повернуть в часы читателя.
///
/// Получасовые пояса округляются до часа: столбик и так шириной в час.
List<int> shiftHoursToLocal(List<int> utcHours, Duration offset) {
  if (utcHours.isEmpty) return const [];
  final shift = (offset.inMinutes / 60).round();
  final n = utcHours.length;
  return List<int>.generate(n, (i) => utcHours[((i - shift) % n + n) % n]);
}
