// Обложка уведомления «А» (28.11.2026) — для своих уведомлений приложения.
//
// Сообщение партнёра доходит и сокетом, пока приложение живо в фоне: тогда
// уведомление ставит само приложение (`PbPushService`), а не пуш сервера.
// Выглядеть оно обязано так же, поэтому здесь тот же сборщик, что у сервера
// (`pocketbase/hotpath/push_cover.py`), строка в строку. Сверка —
// `test/models/push_cover_test.dart` по примерам сервера
// (`test/fixtures/push_cover_cases.json`).
//
// Рисует обложку Android (`notif/NotifCover.kt`, канал `love_app/notif`).

import '../l10n/push_cover_texts.dart';

/// Откуда брать картинки: каталог приложения или примеры в тесте.
abstract class CoverLook {
  /// Неподвижный кадр записи каталога (`art_act_miss`, `gift_bouquet`,
  /// `frame_hearts`) или null.
  String? still(String catalogId);

  /// Котик «Моти» для настроения [moodId] или null.
  String? moti(String moodId);

  /// Радиус фото под рамкой [key] в единицах 0..100 (`AvatarFrame.hole`).
  double frameHole(String key);
}

const String _files = 'https://togetherly.day/api/files';

/// Куда ведёт нажатие: своё пространство ссылок уведомлений. Ссылки виджетов
/// сами делают дело (`loveapp://miss` шлёт «Скучаю»), уведомление только
/// открывает экран.
const String kCoverOpen = 'loveapp://open/';

/// Кнопки, которые телефон выполняет сам, не открывая приложение.
const Set<String> kCoverNativeActions = {'reply', 'hug', 'read', 'throw'};

/// Код языка как у сервера: первые две буквы, незнакомый — русский.
String coverLanguage(String? code) {
  final c = (code ?? '').trim().toLowerCase();
  final two = c.length >= 2 ? c.substring(0, 2) : c;
  return kPushCoverLanguages.contains(two) ? two : 'ru';
}

String _t(String key, String lang) {
  final variants = kPushCoverTexts[key]!;
  return variants[coverLanguage(lang)] ?? variants['ru']!;
}

String _s(Map<String, Object?> ctx, String key) => (ctx[key] ?? '').toString().trim();

/// `pb://media/<запись>/<файл>` → ссылка; [size] — миниатюра. У `media.file`
/// объявлена одна, 400x400: другой размер PocketBase отдал бы оригиналом.
String _fromMedia(Object? pb, [String? size]) {
  final s = (pb ?? '').toString().trim();
  if (!s.startsWith('pb://')) return s.startsWith('https://') ? s : '';
  return '$_files/${s.substring('pb://'.length)}${size == null ? '' : '?thumb=$size'}';
}

Map<String, Object?> _picture(String? url) =>
    (url != null && url.isNotEmpty) ? {'url': url} : {'app': true};

List<Map<String, Object?>> _buttons(String lang, List<List<String>> items) => [
      for (final item in items)
        {
          'id': item[0],
          'label': _t(item[1], lang),
          if (item.length > 2) 'link': '$kCoverOpen${item[2]}',
        },
    ];

/// Что показать в обложке нового воспоминания. Секретное, «18+» и
/// запечатанная капсула уходят без фото и названия: экран блокировки видят
/// и чужие. Как `memory_ctx` сервера.
Map<String, Object?> memoryCoverContext(Map<String, dynamic>? data, String name) {
  final d = data ?? const {};
  bool on(String k) {
    final v = d[k];
    return v == true || (v is String && v.isNotEmpty) || (v is num && v != 0);
  }

  if (on('isSecret') || on('isAdult') || on('sealed')) return {'from_name': name};
  return {
    'from_name': name,
    'title': '${d['title'] ?? ''}'.trim(),
    'photo': '${d['imageUrl'] ?? ''}',
  };
}

/// Обложка вида [kind] на языке [lang] или null, если вид обложки не знает
/// (уведомление показывается по-старому). Повторяет `cover()` сервера.
Map<String, Object?>? buildPushCover(
    String kind, String lang, Map<String, Object?> ctx, CoverLook look) {
  final fromName = _s(ctx, 'from_name');
  final name = fromName.isNotEmpty ? fromName : _t('partner', lang);
  final body = _s(ctx, 'body');
  final title = _s(ctx, 'title');
  String or(String a, String b) => a.isNotEmpty ? a : b;

  final base = <String, Object?>{'v': 1, 'kind': kind, 'failed': _t('c_failed', lang)};
  final group = (ctx['group_id'] ?? '').toString();
  if (group.isNotEmpty) base['group'] = group;

  switch (kind) {
    case 'miss':
      return {
        ...base,
        'kicker': '${_t('c_miss', lang)} · $name',
        'title': or(title, _t('miss_title', lang)),
        'body': body,
        'tone': 'miss',
        'art': _picture(look.still('art_act_miss')),
        'actions': _buttons(lang, [
          ['hug', 'a_hug_back'],
          ['write', 'a_write', 'chat'],
        ]),
        'link': '${kCoverOpen}miss',
        'event_id': (ctx['event_id'] ?? '').toString(),
      };
    case 'mood':
      final moodId = _s(ctx, 'mood_id');
      return {
        ...base,
        'kicker': '${_t('c_mood', lang)} · $name',
        'title': or(_s(ctx, 'label'), _t('mood_title', lang)),
        'body': or(body, _t('c_mood_today', lang)),
        'tone': 'mood',
        'art': _picture(moodId.isEmpty ? null : look.moti(moodId)),
        'actions': _buttons(lang, [
          ['mood_back', 'a_mood_back', 'mood'],
        ]),
        'link': '${kCoverOpen}mood',
      };
    case 'chat':
      final frame = _s(ctx, 'frame');
      // Аватар оригиналом: он маленький, а миниатюра 400x400 тяжелее.
      final avatar = _fromMedia(ctx['avatar']);
      final ts = ctx['ts'];
      return {
        ...base,
        'kicker': _t('message', lang),
        'title': name,
        'body': body,
        'tone': 'chat',
        'art': _picture(avatar),
        'actions': _buttons(lang, [
          ['reply', 'a_reply'],
          ['hug', 'a_hug'],
          ['read', 'a_read'],
        ]),
        'link': '${kCoverOpen}chat',
        'chat': {
          'from_uid': (ctx['from_uid'] ?? '').toString(),
          'from_name': name,
          'group_id': group,
          'message_id': (ctx['message_id'] ?? '').toString(),
          'ts': ts is num ? ts.toInt() : int.tryParse('${ts ?? ''}') ?? 0,
          'avatar': avatar,
          'frame': frame.isEmpty ? '' : (look.still('frame_$frame') ?? ''),
          'frame_hole': _whole(frame.isEmpty ? 31 : look.frameHole(frame)),
          'you': _t('c_you', lang),
          'queued': _t('c_queued', lang),
          'hugged': _t('c_hugged', lang),
          'image': _fromMedia(ctx['photo'], '400x400'),
          'quick': [_t('q_hug', lang), _t('q_miss', lang), _t('q_love', lang)],
        },
      };
    case 'memory':
      final photo = _fromMedia(ctx['photo'], '400x400');
      return {
        ...base,
        'kicker': '${_t('c_memory', lang)} · $name',
        'title': or(title, _t('c_memory_new', lang)),
        'body': body,
        'tone': 'memory',
        'art': photo.isNotEmpty ? {'url': photo, 'auth': true} : {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_watch', 'memories'],
        ]),
        'link': '${kCoverOpen}memories',
      };
    case 'date':
      final symbol = _s(ctx, 'symbol');
      return {
        ...base,
        'kicker': '${_t('c_date_new', lang)} · $name',
        'title': or(title, _t('date_untitled', lang)),
        'body': body,
        'tone': 'date',
        'art': symbol.isNotEmpty ? {'symbol': symbol} : {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_open', 'dates'],
        ]),
        'link': '${kCoverOpen}dates',
      };
    case 'snowball':
      return {
        ...base,
        'kicker': '${_t('c_snow', lang)} · $name',
        'title': or(title, _t('snow_title', lang)),
        'body': or(body, _t('snow_body', lang)),
        'tone': 'snow',
        'art': _picture(look.still('art_act_wake')),
        'actions': _buttons(lang, [
          ['throw', 'a_throw'],
        ]),
        'link': '${kCoverOpen}home',
      };
    case 'gift':
      final key = _s(ctx, 'gift_key');
      // Подарком бывает и рамка (`frame_<ключ>` — своя запись каталога).
      final record = key.startsWith('frame_') ? key : (key.isNotEmpty ? 'gift_$key' : '');
      return {
        ...base,
        'kicker': '${_t('c_gift', lang)} · $name',
        'title': or(title, _t('c_gift', lang)),
        'body': body,
        'tone': 'gift',
        'art': _picture(record.isEmpty ? null : look.still(record)),
        'actions': _buttons(lang, [
          ['open', 'a_open_gift', 'gifts'],
        ]),
        'link': '${kCoverOpen}gifts',
      };
    case 'comment':
      final photo = _fromMedia(ctx['photo'], '400x400');
      return {
        ...base,
        'kicker': '${_t('c_comment', lang)} · $name',
        'title': or(title, _t('c_memory', lang)),
        'body': body,
        'tone': 'memory',
        'art': photo.isNotEmpty ? {'url': photo, 'auth': true} : {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_open', 'memories'],
        ]),
        'link': '${kCoverOpen}memories',
      };
    case 'draw':
      return {
        ...base,
        'kicker': '${_t('c_draw', lang)} · $name',
        'title': title,
        'body': body,
        'tone': 'draw',
        'art': _picture(look.still('art_act_draw')),
        'actions': _buttons(lang, [
          ['open', 'a_canvas', 'draw'],
        ]),
        'link': '${kCoverOpen}draw',
      };
    case 'plusgift':
      return {
        ...base,
        'kicker': '${_t('c_gift', lang)} · $name',
        'title': title,
        'body': body,
        'tone': 'plus',
        'art': {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_open', 'plus'],
        ]),
        'link': '${kCoverOpen}plus',
      };
    case 'pair_reset':
    case 'security':
      return {
        ...base,
        'kicker': _t('c_security', lang),
        'title': title,
        'body': body,
        'tone': 'app',
        'art': {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_open', 'home'],
        ]),
        'link': '${kCoverOpen}home',
      };
    // ── От самого приложения: обложка — иконка, картинка — в развёрнутом ──
    case 'date_remind':
      final symbol = _s(ctx, 'symbol');
      return {
        ...base,
        'kicker': _t('c_date', lang),
        'title': title,
        'body': body,
        'tone': 'date',
        'art': {'app': true},
        'art_big': symbol.isNotEmpty ? {'symbol': symbol} : {'app': true},
        'actions': _buttons(lang, [
          ['open', 'a_open', 'dates'],
        ]),
        'link': '${kCoverOpen}dates',
      };
    case 'evening':
      return {
        ...base,
        'kicker': _t('c_evening', lang),
        'title': title,
        'body': body,
        'tone': 'evening',
        'art': {'app': true},
        'art_big': _picture(look.still('art_act_rest')),
        'actions': _buttons(lang, [
          ['mood', 'a_mood', 'mood'],
          ['task', 'a_task', 'task'],
        ]),
        'link': '${kCoverOpen}mood',
      };
    case 'chest':
      return {
        ...base,
        'kicker': _t('c_chest', lang),
        'title': title,
        'body': body,
        'tone': 'chest',
        'art': {'app': true},
        'art_big': _picture(look.still('art_chest_idle2')),
        'actions': _buttons(lang, [
          ['chest', 'a_chest', 'chest'],
        ]),
        'link': '${kCoverOpen}chest',
      };
  }
  return null;
}

/// Целое число без дробной части — как его пишет сервер (27, а не 27.0).
num _whole(double v) => v == v.roundToDouble() ? v.toInt() : v;
