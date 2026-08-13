import 'package:flutter/material.dart';

import '../../models/gift.dart';
import '../../models/partner_profile.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';

/// Что осталось от подарков одного вида: даты, записки, ответы, место встречи.
///
/// До этого листа записку показывал только момент вручения. Кто закрыл его не
/// дочитав, письмо терял насовсем, хотя текст всё это время лежал в базе —
/// именно с такой жалобой пришёл первый человек.
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
    background: scheme.surfaceContainer,
    builder: (_) => SheetScaffold(
      title: gift.title,
      child: _MemoList(
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
  );
}

class _MemoList extends StatelessWidget {
  const _MemoList({
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

  String _tr(String r, String e) => ru ? r : e;

  /// «14 июля» для этого года и «14 июля 2025» для прошлых: без года две
  /// годовщины подряд читаются как одна.
  String _dateLabel(DateTime? date) {
    if (date == null) return _tr('дата потерялась', 'date lost');
    final day = strings.dayLogDate(date);
    return date.year == DateTime.now().year ? day : '$day ${date.year}';
  }

  String _senderLabel(String uid) {
    switch (giftSenderOf(
        senderUid: uid, myUid: myUid, shelfOwnerUid: shelfOwnerUid)) {
      case GiftSender.me:
        return _tr('от вас', 'from you');
      case GiftSender.counterpart:
        final name = counterpartName?.trim();
        if (name != null && name.isNotEmpty) {
          return _tr('от $name', 'from $name');
        }
        return _tr('от партнёра', 'from your partner');
      case GiftSender.unknown:
        return _tr('от партнёра', 'from your partner');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (memos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          _tr('Этого подарка на полке ещё нет.',
              'This gift is not on the shelf yet.'),
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }

    final withText = memos.where((m) => m.hasText).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            withText == 0
                ? _tr('Слов к этому подарку не прилагалось.',
                    'No words came with this gift.')
                : _tr('Записки хранятся здесь и открываются в любой момент.',
                    'Notes are kept here and open any time.'),
            style: TextStyle(
                fontSize: 13.5, height: 1.4, color: scheme.onSurfaceVariant),
          ),
        ),
        // Полка иногда собирает десятки одинаковых подарков — список должен
        // прокручиваться внутри листа, а не растягивать его на весь экран.
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: memos.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _MemoCard(
              memo: memos[i],
              scheme: scheme,
              ru: ru,
              strings: strings,
              dateLabel: _dateLabel(memos[i].sentAt),
              senderLabel: _senderLabel(memos[i].senderUid),
            ),
          ),
        ),
      ],
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
  });

  final GiftMemo memo;
  final ColorScheme scheme;
  final bool ru;
  final AppStrings strings;
  final String dateLabel;
  final String senderLabel;

  String _tr(String r, String e) => ru ? r : e;

  @override
  Widget build(BuildContext context) {
    final meeting = <String>[
      if (memo.place.isNotEmpty) memo.place,
      if (memo.date != null)
        '${strings.dayLogDate(memo.date!)}, '
            '${memo.date!.hour.toString().padLeft(2, '0')}:'
            '${memo.date!.minute.toString().padLeft(2, '0')}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dateLabel · $senderLabel',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant),
          ),
          if (memo.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              memo.note,
              style: TextStyle(
                  fontSize: 15, height: 1.45, color: scheme.onSurface),
            ),
          ],
          if (memo.reply.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Sub(
              label: _tr('Ответ', 'Reply'),
              text: memo.reply,
              scheme: scheme,
            ),
          ],
          if (meeting.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Sub(
              label: _tr('Встреча', 'Meeting'),
              text: meeting,
              scheme: scheme,
            ),
          ],
          if (!memo.hasText) ...[
            const SizedBox(height: 6),
            Text(
              _tr('Без записки', 'No note'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Вложенная строка «Ответ» или «Встреча» — подложка ниже карточки, чтобы
/// чужие слова не путались с запиской дарителя.
class _Sub extends StatelessWidget {
  const _Sub({
    required this.label,
    required this.text,
    required this.scheme,
  });

  final String label;
  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: scheme.primary),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: TextStyle(
                fontSize: 14, height: 1.4, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
