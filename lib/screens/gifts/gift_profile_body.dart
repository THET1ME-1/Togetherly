import 'package:flutter/material.dart';
import '../profile/miss_you_week_chart.dart';
import '../../theme/profile_theme.dart';

import '../../models/partner_profile.dart';
import '../../widgets/avatar_widget.dart';
import '../../services/locale_service.dart';
import '../../services/pb_data_service.dart';
import '../../services/pocketbase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/m3_loading.dart';
import 'gift_memo_sheet.dart';
import '../../widgets/common/scaled_asset.dart';

/// Тело профиля-«Открытки»: шапка с аватаром и чипами, полка подарков со
/// счётчиками, столбики «скучаю» по дням недели.
///
/// Один и тот же виджет обслуживает экран партнёра ([isSelf] = false) и личный
/// профиль на странице «Профиль» ([isSelf] = true) — меняются лишь заголовки и
/// возможность тапнуть по аватару, чтобы отредактировать свой профиль.
/// Данные грузятся по [uid]: подарки, полученные этим человеком, и его дни
/// «скучаю». Возвращает [Column] без собственной прокрутки — родитель сам
/// решает, обернуть ли в [ListView]/[RefreshIndicator] или встроить в скролл.
class GiftProfileBody extends StatefulWidget {
  const GiftProfileBody({
    super.key,
    required this.theme,
    required this.groupId,
    required this.uid,
    required this.name,
    this.avatarUrl,
    this.daysTogether,
    this.isSelf = false,
    this.onAvatarTap,
    this.showHeader = true,
    this.counterpartName,
    this.showMissWeek = true,
    this.showGiftsTitle = true,
  });

  final AppTheme theme;
  final String groupId;
  final String uid;
  final String name;
  final String? avatarUrl;
  final int? daysTogether;

  /// true — личный профиль (свои данные, тап по аватару правит профиль).
  final bool isSelf;

  /// Тап по аватару (для личного профиля — открыть редактирование).
  final VoidCallback? onAvatarTap;

  /// false — не рисовать внутреннюю шапку (её даёт ProfileHero сверху).
  final bool showHeader;

  /// Имя второго в паре — им подписаны записки в листе подарка. Пусто —
  /// подпись станет обезличенной («от партнёра»), но лист всё равно откроется.
  final String? counterpartName;

  /// false — не рисовать столбики «Я скучаю». Нужно экрану одной полки, где
  /// кроме подарков не должно быть ничего.
  final bool showMissWeek;

  /// false — полка без заголовка над ней: на своём экране название уже стоит
  /// в шапке, и второй раз его писать незачем.
  final bool showGiftsTitle;

  @override
  State<GiftProfileBody> createState() => GiftProfileBodyState();
}

/// Публичен, чтобы родитель мог дёрнуть [reload] из [RefreshIndicator].
class GiftProfileBodyState extends State<GiftProfileBody> {
  List<GiftTally> _shelf = const [];

  /// Сырые записи подарков: из них лист собирает записки по тапу на полке.
  List<Map<String, dynamic>> _gifts = const [];
  WeekStats _week = const WeekStats([0, 0, 0, 0, 0, 0, 0]);
  int _giftsTotal = 0;
  int _missTotal = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final data = PbDataService();
    // Свои подарки собираем по ВСЕМ связям (groupId пустой): полка пустовала,
    // когда подарок пришёл в другой паре. Партнёрская — строго его группа.
    final gifts = await data.fetchGiftsFor(
      groupId: widget.isSelf ? '' : widget.groupId,
      uid: widget.uid,
    );
    final miss =
        await data.fetchMissYouFor(groupId: widget.groupId, uid: widget.uid);
    if (!mounted) return;
    setState(() {
      _gifts = gifts;
      _shelf = tallyGifts(gifts);
      _giftsTotal = gifts.length;
      _week = parseWeekdays(miss?['by_weekday'] as String?);
      _missTotal = (miss?['count'] as num?)?.toInt() ?? 0;
      _loading = false;
    });
  }

  /// Есть ли у подарков этого вида слова — по этому полка ставит метку.
  bool _hasTextOf(String key) =>
      memosOfKey(_gifts, key).any((m) => m.hasText);

  void _openMemos(GiftTally tally) {
    showGiftMemoSheet(
      context,
      theme: widget.theme,
      gift: tally.gift,
      memos: memosOfKey(_gifts, tally.key),
      myUid: PocketBaseService().userId ?? '',
      shelfOwnerUid: widget.uid,
      counterpartName: widget.counterpartName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final s = LocaleService.current;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: M3Loading(color: Color(0xFFFF7E8B))),
      );
    }
    return Column(
      children: [
        if (widget.showHeader) ...[
          _Hero(
            theme: t,
            uid: widget.uid,
            name: widget.name,
            avatarUrl: widget.avatarUrl,
            daysTogether: widget.daysTogether,
            giftsChip: s.partnerGiftsChip(_giftsTotal),
            missChip: s.partnerMissChip(_missTotal),
            onAvatarTap: widget.onAvatarTap,
          ),
          const SizedBox(height: 20),
        ],
        if (widget.showGiftsTitle)
          _Block(
            theme: t,
            title: widget.isSelf ? s.selfGiftsTitle : s.partnerGiftsTitle,
            trailing: _giftsTotal > 0 ? '$_giftsTotal' : null,
            child: _shelf.isEmpty
                ? _Empty(theme: t, text: s.partnerGiftsEmpty)
                : _Shelf(
                    theme: t,
                    shelf: _shelf,
                    hasTextOf: _hasTextOf,
                    onTap: _openMemos,
                  ),
          )
        else if (_shelf.isEmpty)
          _Empty(theme: t, text: s.partnerGiftsEmpty)
        else
          _Shelf(
            theme: t,
            shelf: _shelf,
            hasTextOf: _hasTextOf,
            onTap: _openMemos,
          ),
        if (widget.showMissWeek) ...[
          const SizedBox(height: 20),
          _Block(
            theme: t,
            title: widget.isSelf ? s.selfMissTitle : s.partnerMissTitle,
            child: _week.isEmpty
                ? _Empty(theme: t, text: s.partnerMissEmpty)
                : MissYouWeekChart(theme: t, week: _week),
          ),
        ],
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.theme,
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.daysTogether,
    required this.giftsChip,
    required this.missChip,
    this.onAvatarTap,
  });

  final AppTheme theme;
  final String uid;
  final String name;
  final String? avatarUrl;
  final int? daysTogether;
  final String giftsChip;
  final String missChip;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    // AvatarWidget сам разбирается с форматом ссылки и кэшем: свой
    // NetworkImage показывал пустой круг на аватарах из группы.
    Widget avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.cardSurface,
      ),
      child: AvatarWidget(
        uid: uid,
        liveUrl: avatarUrl,
        name: name,
        size: 82,
        primary: theme.primary,
      ),
    );
    if (onAvatarTap != null) {
      avatar = GestureDetector(onTap: onAvatarTap, child: avatar);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.primary.withValues(alpha: 0.18),
            theme.primary.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Column(
        children: [
          avatar,
          const SizedBox(height: 10),
          Text(name,
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: theme.textPrimary)),
          if (daysTogether != null) ...[
            const SizedBox(height: 2),
            Text(s.partnerDaysTogether(daysTogether!),
                style: TextStyle(fontSize: 13.5, color: theme.textSecondary)),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _Chip(
                  theme: theme,
                  icon: Icons.card_giftcard_rounded,
                  text: giftsChip),
              _Chip(theme: theme, icon: Icons.mail_rounded, text: missChip),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.theme, required this.icon, required this.text});

  final AppTheme theme;

  /// Иконка вместо прежнего эмодзи в строке: та красилась системой и в тёмной
  /// теме светилась ярче самого числа.
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: theme.cardSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.primary),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: theme.textPrimary)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.theme,
    required this.title,
    required this.child,
    this.trailing,
  });

  final AppTheme theme;
  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                        fontFamily: ProfileTheme.displayFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: cs.primary)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.theme,
    required this.shelf,
    required this.hasTextOf,
    required this.onTap,
  });

  final AppTheme theme;
  final List<GiftTally> shelf;

  /// Хранит ли этот подарок записку — по нему рисуется уголок с точкой.
  final bool Function(String key) hasTextOf;

  final void Function(GiftTally tally) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: shelf.map((t) {
        final withText = hasTextOf(t.key);
        return SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTap(t),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: Center(
                      child: ScaledAsset(t.gift.asset, side: 46),
                    ),
                  ),
                ),
              ),
              // Точка в нижнем углу: у этого подарка есть что перечитать.
              // Без неё полка выглядит нажимаемой везде одинаково, а слова
              // приложены далеко не к каждому.
              if (withText)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                  ),
                ),
              if (t.count > 1)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${t.count}',
                        style: TextStyle(
                            fontFamily: ProfileTheme.displayFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.onPrimary)),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.theme, required this.text});

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(theme).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text,
          style: TextStyle(
              fontFamily: ProfileTheme.bodyFont,
              fontSize: 13.5,
              color: cs.onSurfaceVariant)),
    );
  }
}
