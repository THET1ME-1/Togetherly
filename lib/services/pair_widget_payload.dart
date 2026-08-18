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
Map<String, String> pairWidgetPayload({
  WidgetData? my,
  WidgetData? partner,
  String myFallbackName = 'Я',
  String partnerFallbackName = 'Партнёр',
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
  }

  return out;
}

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

PairWidgetMedia pairWidgetMedia({WidgetData? my, WidgetData? partner}) =>
    PairWidgetMedia(
      myPhoto: my == null ? null : pairPhotoOf(my),
      partnerPhoto: partner == null ? null : pairPhotoOf(partner),
      myAvatar: my?.avatarUrl,
      partnerAvatar: partner?.avatarUrl,
      myMoodEmoji: my?.moodEmoji,
      partnerMoodEmoji: partner?.moodEmoji,
      myIosPhotos: my == null ? null : iosPhotosOf(my),
      partnerIosPhotos: partner == null ? null : iosPhotosOf(partner),
    );

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
