import '../models/widget_data.dart';

/// Что писать в общий контейнер для парного виджета.
///
/// Половину, про которую данных НЕТ, трогать нельзя. Служба подписывается на
/// свои данные по uid из сессии PocketBase и при пустом uid молча выходит, а на
/// партнёра подписка идёт по uid из пары. На iOS приложение часто поднимают
/// тихим пушем на пару секунд, сессия к этому моменту может быть ещё не
/// восстановлена — и `_myData` остаётся null. Прежний код в этом состоянии писал
/// пустые строки, и своя половина виджета обнулялась: ни статуса, ни настроения,
/// ни музыки (связка Android — iOS, 17.08.2026).
///
/// Пустое поле при живых данных — другое дело: человек убрал статус осознанно,
/// и виджет обязан это показать. Поэтому «нет данных» и «поле пустое» здесь
/// строго разные случаи.
///
/// [pairChanged] — виджет пересобирают для ДРУГОЙ пары, чем в прошлый раз. Тут
/// «данных нет» значит уже не «подожди, сейчас приедут», а «этой половине
/// взяться неоткуда»: у новой связи запись `widget_data` появляется не сразу, и
/// молчание оставляло на рабочем столе имя и настроение прежней пары. Так
/// собиралась смесь двух связей в одной картинке (снимок от 04.09.2026).
Map<String, String> pairWidgetPayload({
  WidgetData? my,
  WidgetData? partner,
  String myFallbackName = 'Я',
  String partnerFallbackName = 'Партнёр',
  bool pairChanged = false,
}) {
  final out = <String, String>{};

  if (my != null) {
    out['my_name'] =
        my.displayName.isNotEmpty ? my.displayName : myFallbackName;
    out['my_mood'] = my.moodLabel;
    out['my_status'] = my.status;
    out['my_message'] = my.message;
    out['my_music_title'] = my.musicTitle ?? '';
    out['my_music_artist'] = my.musicArtist ?? '';
  } else if (pairChanged) {
    for (final key in _myTextKeys) {
      out[key] = '';
    }
  }

  if (partner != null) {
    out['partner_name'] = partner.displayName.isNotEmpty
        ? partner.displayName
        : partnerFallbackName;
    out['partner_mood'] = partner.moodLabel;
    out['partner_status'] = partner.status;
    out['partner_message'] = partner.message;
    out['partner_music_title'] = partner.musicTitle ?? '';
    out['partner_music_artist'] = partner.musicArtist ?? '';
  } else if (pairChanged) {
    for (final key in _partnerTextKeys) {
      out[key] = '';
    }
  }

  return out;
}

const List<String> _myTextKeys = [
  'my_name',
  'my_mood',
  'my_status',
  'my_message',
  'my_music_title',
  'my_music_artist',
];

const List<String> _partnerTextKeys = [
  'partner_name',
  'partner_mood',
  'partner_status',
  'partner_message',
  'partner_music_title',
  'partner_music_artist',
];

/// Ссылки на картинки обеих половин: фото, аватар, значок настроения.
///
/// То же правило, что и у текстовых ключей, только для файлов — и оно было
/// упущено 17.08.2026. Тексты половину без данных уже не трогали, а фото,
/// аватар и значок настроения пересобирались из `my?.photoUrl` на каждом
/// проходе: при `my == null` получалась пустая строка, ключ обнулялся, а файл
/// удалялся из общего контейнера вместе с ним. Самоотчёт с iPhone тестера в
/// ночь на 18.08 (сборка 1.29.1+202) показал именно эту картину: имена и
/// настроения на месте, все пути к файлам пусты.
///
/// `null` — данных о половине нет, ключ не трогаем. Пустая строка — данные
/// живые, а картинку человек убрал: тогда стираем.
class PairWidgetMedia {
  const PairWidgetMedia({
    this.myPhoto,
    this.partnerPhoto,
    this.myAvatar,
    this.partnerAvatar,
    this.myMoodEmoji,
    this.partnerMoodEmoji,
    this.myIosPhotos,
    this.partnerIosPhotos,
  });

  final String? myPhoto;
  final String? partnerPhoto;
  final String? myAvatar;
  final String? partnerAvatar;
  final String? myMoodEmoji;
  final String? partnerMoodEmoji;

  /// Снимки для фото-виджетов iPhone: `null` — половина не загружена.
  final List<String>? myIosPhotos;
  final List<String>? partnerIosPhotos;
}

/// [pairChanged] — то же правило, что у текстов: виджет собирают для другой
/// пары, и картинке половины без данных взяться неоткуда. Пустая строка тут
/// значит «сотри», иначе на столе остаётся лицо прежней связи.
PairWidgetMedia pairWidgetMedia({
  WidgetData? my,
  WidgetData? partner,
  bool pairChanged = false,
}) {
  final bool clearMine = my == null && pairChanged;
  final bool clearTheirs = partner == null && pairChanged;
  return PairWidgetMedia(
    myPhoto: my == null ? (clearMine ? '' : null) : pairPhotoOf(my),
    partnerPhoto:
        partner == null ? (clearTheirs ? '' : null) : pairPhotoOf(partner),
    myAvatar: my?.avatarUrl ?? (clearMine ? '' : null),
    partnerAvatar: partner?.avatarUrl ?? (clearTheirs ? '' : null),
    myMoodEmoji: my?.moodEmoji ?? (clearMine ? '' : null),
    partnerMoodEmoji: partner?.moodEmoji ?? (clearTheirs ? '' : null),
    myIosPhotos: my == null ? (clearMine ? const <String>[] : null) : iosPhotosOf(my),
    partnerIosPhotos: partner == null
        ? (clearTheirs ? const <String>[] : null)
        : iosPhotosOf(partner),
  );
}

/// Какое фото показывает половина парного виджета — своё и партнёрское правило
/// одно и то же с 13.08.2026 (см. `WidgetService.pairPhotoOfPartner`).
String pairPhotoOf(WidgetData? d) => d?.photoUrl ?? '';

/// Какие снимки показывать в фото-виджетах iPhone: сначала карусель «для
/// партнёра», затем снимок парного виджета.
List<String> iosPhotosOf(WidgetData? d) {
  if (d == null) return const [];
  final out = <String>[];
  for (final url in d.photoForPartnerUrls) {
    if (url.isNotEmpty && !out.contains(url)) out.add(url);
  }
  final single = d.photoForPartnerUrl ?? '';
  if (single.isNotEmpty && !out.contains(single)) out.add(single);
  final pair = pairPhotoOf(d);
  if (pair.isNotEmpty && !out.contains(pair)) out.add(pair);
  return out;
}

/// Ключ парного виджета, принадлежащий одной паре: `love_<пара>_<поле>`.
///
/// Так уже живут «Настроение», «Дни вместе», «Скучаю», заметка и кольца года.
/// Парный виджет держался на общих ключах дольше всех, и потому у человека с
/// двумя связями показывал ту пару, чья синхронизация прошла последней.
String pairWidgetKey(String groupId, String key) =>
    groupId.isEmpty ? key : 'love_${groupId}_$key';

/// Тот же набор ключей, но принадлежащий паре.
Map<String, String> pairWidgetKeysFor(String groupId, Map<String, String> keys) =>
    {for (final e in keys.entries) pairWidgetKey(groupId, e.key): e.value};

/// Отметка «ключи этой пары в контейнере уже разложены».
///
/// Нативный виджет читает её первой: нет отметки — значит приложение ещё не
/// обновляло контейнер после установки новой сборки, и читать надо старые общие
/// ключи, иначе виджет опустеет до первого захода в приложение.
String pairWidgetReadyKey(String groupId) => 'love_${groupId}_ready';

/// Указатель «последняя пара парного виджета» — по нему виджет находит свои
/// ключи там, где привязки к экземпляру нет (iPhone).
const String kPairWidgetLatestGroupKey = 'love_latest_group';

/// Пара, которую фон обновляет за этот проход.
class PairRefreshTarget {
  const PairRefreshTarget(this.groupId, {required this.shared});

  final String groupId;

  /// Пишет ли эта пара ещё и старые общие ключи. Право есть только у открытой
  /// в приложении: общий набор один на всех, и делить его нельзя.
  final bool shared;
}

/// Сколько пар фон успевает обновить за одно пробуждение.
///
/// Пробуждение короткое (на iPhone — секунды), а связей у человека бывает и
/// десяток: взяться за все — значит не успеть ни одной. Открытая пара всё равно
/// идёт первой, поэтому обрезаем хвост.
const int kMaxPairsPerRefresh = 5;

/// Какие пары обновлять и кто из них пишет общие ключи.
///
/// Фоновое обновление брало единственную пару из `love_widget_group_id`, и
/// виджет второй связи застывал до переключения в приложении.
List<PairRefreshTarget> pairsToRefresh({
  required List<String> groups,
  required String activeGroupId,
}) {
  final seen = <String>{};
  final out = <PairRefreshTarget>[];
  if (activeGroupId.isNotEmpty) {
    seen.add(activeGroupId);
    out.add(PairRefreshTarget(activeGroupId, shared: true));
  }
  for (final g in groups) {
    if (g.isEmpty || !seen.add(g)) continue;
    out.add(PairRefreshTarget(g, shared: false));
    if (out.length >= kMaxPairsPerRefresh) break;
  }
  return out;
}

/// Ключи с файлами: по ним чистится и запись, и сама картинка в контейнере.
const List<String> kPairWidgetFileKeys = [
  'my_photo_path',
  'partner_photo_path',
  'my_avatar_path',
  'partner_avatar_path',
  'my_mood_emoji_path',
  'partner_mood_emoji_path',
  'ios_self_photo_path',
  'ios_partner_photo_path',
];

/// Что записать в контейнер, когда пара распалась.
///
/// Отвязка раньше обходилась обычной синхронизацией с пустой моделью: та писала
/// пустые строки во все ключи и тем самым чистила виджет. Теперь половина без
/// данных не трогается вовсе (иначе фото стиралось на каждом холодном старте),
/// поэтому распад пары надо отрабатывать явно — иначе на рабочем столе остаются
/// имя, настроение и фото бывшего партнёра, а на iPhone обновить их некому.
Map<String, String> pairWidgetClearPayload() => {
      for (final key in const [
        'my_name',
        'my_mood',
        'my_status',
        'my_message',
        'my_music_title',
        'my_music_artist',
        'my_photo_url',
        'my_avatar_url',
        'partner_name',
        'partner_mood',
        'partner_status',
        'partner_message',
        'partner_music_title',
        'partner_music_artist',
        'partner_photo_url',
        'partner_avatar_url',
        'ios_partner_photo_author',
        'ios_photo_day_path',
        'ios_photo_day_author',
        'ios_photo_catalog_self',
        'ios_photo_catalog_partner',
        'ios_photo_catalog_day',
        ...kPairWidgetFileKeys,
      ])
        key: '',
    };

/// Пора ли стирать виджет пары.
///
/// Стираем ровно при распаде: пара была и не стало. Отвязка от группы этим
/// признаком НЕ является — экран зовёт её и при обычном переключении между
/// связями (сперва отвязка, следом привязка к новой). 18.08.2026 очистка,
/// повешенная на отвязку, затёрла тексты у человека с двумя связями: на
/// рабочем столе пропали имена и настроения, а гонка с синхронизацией оставила
/// кашу — часть путей пуста, часть на месте.
bool shouldClearPairWidget({required bool wasPaired, required bool isPaired}) =>
    wasPaired && !isPaired;

/// Привязка виджета к паре: что положить в общий контейнер, чтобы виджет
/// понял, чью половину рисовать.
///
/// Ключи пишутся при каждой синхронизации, а не только при смене группы.
/// Отчёты `widget-diag` за 23.08.2026 показали 19 iPhone, где имена обеих
/// половин записаны, а `love_widget_group_id` пуст: виджет рисует
/// «Подключите партнёра» при живой паре. Записывал привязку один
/// `bindToGroup`, и при той же группе он выходит первой строкой — промах
/// записи (на iOS `home_widget` отвечает ошибкой, пока не задан App Group)
/// исправить было уже нечем до самой смены пары.
///
/// Пустую группу сюда не кладём: распад пары чистит `clearPairWidgetData`,
/// и затирать привязку на каждом холодном старте, пока сессия не поднялась,
/// нельзя — на iPhone обновить виджет обратно некому.
Map<String, String> pairBindingPayload({
  required String groupId,
  required String partnerUid,
}) =>
    {
      if (groupId.isNotEmpty) 'love_widget_group_id': groupId,
      if (groupId.isNotEmpty && partnerUid.isNotEmpty)
        'love_widget_partner_uid': partnerUid,
    };
