import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import 'gift_profile_body.dart';

/// Полка подарков и ничего больше: плитки видов, счётчик у повторов, точка у
/// тех, к которым приложены слова. Тап по плитке открывает записки.
///
/// Отдельный экран, а не [SelfProfileScreen]: тот показывает всю «Открытку» —
/// шапку с аватаром, чипы и столбики «Я скучаю», — и человек, нажавший «Что
/// вам дарили», попадал во второй профиль вместо подарков.
class GiftShelfScreen extends StatefulWidget {
  const GiftShelfScreen({
    super.key,
    required this.theme,
    required this.groupId,
    required this.selfUid,
    required this.selfName,
    this.partnerName,
  });

  final AppTheme theme;
  final String groupId;
  final String selfUid;
  final String selfName;

  /// Имя партнёра — им подписаны записки к подаркам.
  final String? partnerName;

  @override
  State<GiftShelfScreen> createState() => _GiftShelfScreenState();
}

class _GiftShelfScreenState extends State<GiftShelfScreen> {
  // Ключ в поле, а не в build(): иначе pull-to-refresh пересоздаёт тело и
  // сбрасывает уже загруженную полку.
  final _bodyKey = GlobalKey<GiftProfileBodyState>();

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.themeFor(widget.theme).colorScheme;
    final s = LocaleService.current;
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: cs.onSurface),
          title: Text(
            s.selfGiftsTitle,
            style: TextStyle(
              fontFamily: ProfileTheme.displayFont,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async =>
              await (_bodyKey.currentState?.reload() ?? Future.value()),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).padding.bottom + 28,
            ),
            children: [
              GiftProfileBody(
                key: _bodyKey,
                theme: widget.theme,
                groupId: widget.groupId,
                uid: widget.selfUid,
                name: widget.selfName,
                isSelf: true,
                counterpartName: widget.partnerName,
                showHeader: false,
                showGiftsTitle: false,
                showMissWeek: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
