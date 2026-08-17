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
