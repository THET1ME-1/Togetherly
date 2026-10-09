import 'package:flutter/material.dart';

import '../../dict_strings.dart' show zhForEnglishIfZh;
import '../../models/gift.dart';
import '../../models/partner_profile.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/common/gift_image.dart';
import '../../widgets/connect_expressive.dart';
import '../../widgets/gifts/gift_photo_card.dart';

/// Что осталось от подарков одного вида: даты, записки, ответы, место встречи.
///
/// До этого листа записку показывал только момент вручения. Кто закрыл его не
/// дочитав, письмо терял насовсем, хотя текст всё это время лежал в базе —
/// именно с такой жалобой пришёл первый человек.
///
/// Вид — вариант А макета (https://claude.ai/artifact/WopVZAazctPjMYiZiUiY3g):
/// сверху подарок на «печеньке» и сколько раз его дарили, ниже карточка на
/// каждый раз. Прежний лист называли кривым: мелкая серая строка сверху,
/// записки одним цветом, ответ и встреча неотличимы друг от друга.
Future<void> showGiftMemoSheet(
  BuildContext context, {
  required AppTheme theme,
  required Gift gift,
  required List<GiftMemo> memos,
  required String myUid,
  String? counterpartName,
  String shelfOwnerUid = '',
}) {
  // Тему и строки снимаем ДО открытия листа: он переживает экран, и обращение
  // к мёртвому состоянию уже стоило проекту сотен падений.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final ru = LocaleService.instance.isRussian;
  final s = LocaleService.current;

  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerLow,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: SheetScaffold(
        child: GiftMemoList(
          gift: gift,
          memos: memos,
          myUid: myUid,
          shelfOwnerUid: shelfOwnerUid,
          counterpartName: counterpartName,
          scheme: scheme,
          ru: ru,
          strings: s,
        ),
      ),
    ),
  );
}

/// «2 раза», «5 раз» — лист говорит по-русски и по-английски.
String giftTimesLabel(int n, {required bool ru}) {
  if (LocaleService.instance.language == AppLanguage.zh) return '$n 次';
  if (!ru) return n == 1 ? 'once' : '$n times';
  final m10 = n % 10, m100 = n % 100;
  final word = (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'раза' : 'раз';
  return '$n $word';
}

class GiftMemoList extends StatelessWidget {
  const GiftMemoList({
    super.key,
    required this.gift,
    required this.memos,
    required this.myUid,
    this.shelfOwnerUid = '',
    required this.counterpartName,
    required this.scheme,
    required this.ru,
    required this.strings,
  });

  final Gift gift;
  final List<GiftMemo> memos;
  final String myUid;

  /// Чья это полка. Нужна, когда своя личность неизвестна: полумёртвая сессия
  /// отдаёт пустой uid, и подпись «от вас» превращалась в «от партнёра» —
  /// человек видел свой подарок как присланный ему (жалоба 14 августа 2026).
  final String shelfOwnerUid;
  final String? counterpartName;
  final ColorScheme scheme;
  final bool ru;
  final AppStrings strings;

  String _tr(String r, String e) => ru ? r : zhForEnglishIfZh(e);

  bool get _zh => LocaleService.instance.language == AppLanguage.zh;

  /// «14 июля» для этого года и «14 июля 2025» для прошлых: без года две
  /// годовщины подряд читаются как одна.
  String _dateLabel(DateTime? date) {
    if (date == null) return _tr('дата потерялась', 'date lost');
    final day = strings.dayLogDate(date);
    if (date.year == DateTime.now().year) return day;
    return _zh ? '${date.year}年$day' : '$day ${date.year}';
  }

  GiftSender _senderOf(String uid) =>
      giftSenderOf(senderUid: uid, myUid: myUid, shelfOwnerUid: shelfOwnerUid);

  String _senderLabel(GiftSender who) {
    switch (who) {
      case GiftSender.me:
        return _tr('от вас', 'from you');
      case GiftSender.counterpart:
        final name = counterpartName?.trim();
        if (name != null && name.isNotEmpty) {
          return _zh ? '来自 $name' : _tr('от $name', 'from $name');
        }
        return _tr('от партнёра', 'from your partner');
      case GiftSender.unknown:
        return _tr('от партнёра', 'from your partner');
      case GiftSender.chest:
        return _tr('из сундука', 'from the chest');
    }
  }

  /// Ответ пишет хозяин полки. Своя полка — «Ваш ответ», чужая — просто
  /// «Ответ», чтобы не выдать партнёрские слова за свои.
  bool get _replyIsMine =>
      shelfOwnerUid.isEmpty || myUid.isEmpty || shelfOwnerUid == myUid;

  @override
  Widget build(BuildContext context) {
    final latest = memos
        .map((m) => m.sentAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final summary = [
      giftTimesLabel(memos.length, ru: ru),
      if (latest != null)
        _zh
            ? '最近一次 ${_dateLabel(latest)}'
            : _tr('последний ${_dateLabel(latest)}',
                'last on ${_dateLabel(latest)}'),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CookieClip(
                size: 84,
                child: ColoredBox(
                  color: scheme.primaryContainer,
                  child: Center(child: GiftImage(gift.key, side: 54)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift.title,
                      style: AppFonts.unbounded(
                          size: 22, weight: 800, color: scheme.onSurface),
                    ),
                    if (memos.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          summary,
                          style: AppFonts.onest(
                              size: 12.5,
                              weight: 700,
                              color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (memos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _tr('Этого подарка на полке ещё нет.',
                    'This gift is not on the shelf yet.'),
                style: AppFonts.onest(size: 15, color: scheme.onSurfaceVariant),
              ),
            )
          else
            // Полка иногда собирает десятки одинаковых подарков — список
            // прокручивается внутри листа, а не растягивает его на весь экран.
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: memos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final who = _senderOf(memos[i].senderUid);
                  return _MemoCard(
                    memo: memos[i],
                    scheme: scheme,
                    ru: ru,
                    strings: strings,
                    dateLabel: _dateLabel(memos[i].sentAt),
                    senderLabel: _senderLabel(who),
                    counterpartName: counterpartName,
                    sender: who,
                    replyIsMine: _replyIsMine,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({
    required this.memo,
    required this.scheme,
    required this.ru,
    required this.strings,
    required this.dateLabel,
    required this.senderLabel,
    required this.sender,
    required this.replyIsMine,
    this.counterpartName,
  });

  final GiftMemo memo;
  final String? counterpartName;
  final ColorScheme scheme;
  final bool ru;
  final AppStrings strings;
  final String dateLabel;
  final String senderLabel;
  final GiftSender sender;
  final bool replyIsMine;

  String _tr(String r, String e) => ru ? r : zhForEnglishIfZh(e);

  @override
  Widget build(BuildContext context) {
    final meeting = <String>[
      if (memo.place.isNotEmpty) memo.place,
      if (memo.date != null)
        '${strings.dayLogDate(memo.date!)}, '
            '${memo.date!.hour.toString().padLeft(2, '0')}:'
            '${memo.date!.minute.toString().padLeft(2, '0')}',
    ].join(' · ');

    // Кто подарил: аватар дарителя, у сундука — его значок.
    final Widget who = sender == GiftSender.chest
        ? Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.redeem_rounded,
                size: 15, color: scheme.onTertiaryContainer),
          )
        : AvatarWidget(
            uid: memo.senderUid,
            // Буква на пустом аватаре — от имени, а не от подписи «от …».
            name: sender == GiftSender.counterpart ? counterpartName : null,
            size: 26,
            primary: scheme.primary,
            showFrame: false,
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              who,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.onest(
                      size: 13.5, weight: 700, color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateLabel,
                style: AppFonts.onest(
                    size: 13, weight: 600, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (memo.photo.isNotEmpty) ...[
            const SizedBox(height: 10),
            GiftPhotoCard(
              photo: memo.photo,
              scheme: scheme,
              authorName: senderLabel,
              maxHeight: 220,
            ),
          ],
          if (memo.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              memo.note,
              style: AppFonts.onest(
                  size: 16, height: 1.45, color: scheme.onSurface),
            ),
          ],
          if (memo.reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.reply_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replyIsMine
                              ? _tr('Ваш ответ', 'Your reply')
                              : _tr('Ответ', 'Reply'),
                          style: AppFonts.onest(
                              size: 11.5, weight: 700, color: scheme.primary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          memo.reply,
                          style: AppFonts.onest(
                              size: 14.5, height: 1.4, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (meeting.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Встреча — пилюлей другого тона: место и время не должны
            // сливаться ни с запиской, ни с ответом.
            Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_rounded,
                      size: 17, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      meeting,
                      style: AppFonts.onest(
                          size: 13,
                          weight: 700,
                          color: scheme.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!memo.hasText) ...[
            const SizedBox(height: 6),
            Text(
              _tr('Без записки', 'No note'),
              style: AppFonts.onest(size: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
