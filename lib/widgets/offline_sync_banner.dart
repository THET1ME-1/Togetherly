import 'dart:async';

import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/offline/connectivity_service.dart';
import '../services/media_service.dart';
import '../services/offline/outbox_service.dart';
import 'common/m3_wave_progress.dart';

/// Глобальная тонкая плашка состояния поверх любого экрана (через
/// `MaterialApp.builder`). Показывается, только когда человеку есть что решать:
/// • офлайн — некликабельная подсказка (сразу);
/// • сжатие видео — своя строка с реальной долей от кодека (десятки секунд, и
///   отправку затеял сам человек);
/// • есть «ядовитые» операции (сервер упорно отверг) — КЛИКАБЕЛЬНАЯ плашка
///   «повторить» (вызывает [OutboxService.retryPoison]), показывается сразу.
///
/// **Про фоновую отправку молчим.** Плашку «Синхронизация…» чинили четырежды
/// (таймаут на операцию, полосы, лимит попыток, счётчик живых операций), и она
/// всё равно всплывала: любой дефект очереди и любая медленная сеть тут же
/// превращались в вечную серую доску поверх шапки. Состояние очереди — кухня
/// приложения, а не решение пользователя; человеку важны только «нет сети» и
/// «правка не сохранилась, повторить». Решение от 26.07.
/// Цвета берутся из текущей темы. Пустые зоны прозрачны для касаний.
class OfflineSyncBanner extends StatelessWidget {
  const OfflineSyncBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              // Material (прозрачный) даёт корректный DefaultTextStyle/Directionality
              // оверлею поверх MaterialApp.builder — иначе Flutter рисует текст с
              // «жёлтым подчёркиванием» (нет Material-предка).
              child: Material(
                type: MaterialType.transparency,
                child: _SyncChips(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncChips extends StatefulWidget {
  @override
  State<_SyncChips> createState() => _SyncChipsState();
}

class _SyncChipsState extends State<_SyncChips> {
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    OutboxService.instance.poisonCount.addListener(_onChange);
    MediaService.instance.compressProgress.addListener(_onChange);
    _connSub =
        ConnectivityService.instance.onOnlineChanged.listen((_) => _onChange());
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    OutboxService.instance.poisonCount.removeListener(_onChange);
    MediaService.instance.compressProgress.removeListener(_onChange);
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poison = OutboxService.instance.poisonCount.value;
    final online = ConnectivityService.instance.isOnline;
    final compressing = MediaService.instance.compressProgress.value;
    final ru = LocaleService.instance.isRussian;
    final scheme = Theme.of(context).colorScheme;

    final chips = <Widget>[];

    if (!online) {
      // Офлайн — показываем сразу (важное состояние).
      chips.add(IgnorePointer(
        child: _chip(
          context,
          icon: Icons.cloud_off_rounded,
          text: ru ? 'Нет сети' : 'Offline',
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
        ),
      ));
    } else if (compressing != null) {
      // Сжатие видео идёт десятки секунд. Без своей строки это выглядело как
      // застрявшая синхронизация, поэтому показываем сразу, без дебаунса, и с
      // настоящей долей от кодека.
      chips.add(IgnorePointer(
        child: _chip(
          context,
          spinner: true,
          text: ru ? 'Сжатие видео…' : 'Compressing video…',
          bg: scheme.surfaceContainerHighest,
          fg: scheme.onSurfaceVariant,
          progress: compressing,
        ),
      ));
    }

    // «Ядовитые» операции — кликабельно: повторить отправку. Показываем сразу.
    if (poison > 0) {
      chips.add(GestureDetector(
        onTap: () => OutboxService.instance.retryPoison(),
        child: _chip(
          context,
          icon: Icons.refresh_rounded,
          text: ru ? 'Не сохранилось — повторить' : "Didn't sync — retry",
          bg: scheme.errorContainer,
          fg: scheme.onErrorContainer,
        ),
      ));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(
            sizeFactor: anim, axisAlignment: -1, child: child),
      ),
      child: chips.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey('${!online}-${poison > 0}-${compressing != null}'),
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in chips)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4), child: c),
                ],
              ),
            ),
    );
  }

  Widget _chip(
    BuildContext context, {
    IconData? icon,
    bool spinner = false,
    required String text,
    required Color bg,
    required Color fg,
    double? progress,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        // Ширина — по содержимому. Раньше стояло растягивание по поперечной оси,
        // и чип с полосой распирало во всю ширину экрана: вместо короткого
        // сообщения получалась серая доска поверх шапки.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _chipRow(context, icon: icon, spinner: spinner, text: text, fg: fg),
            // Волновая полоса под строкой — только там, где доля настоящая
            // (сжатие видео). Ширину задаём сами, иначе она снова растянет чип.
            if (progress != null) ...[
              const SizedBox(height: 7),
              SizedBox(
                width: 150,
                child: M3WaveProgress(
                  value: progress,
                  minHeight: 3,
                  wavelength: 16,
                  color: fg,
                  trackColor: fg.withValues(alpha: 0.22),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _chipRow(
    BuildContext context, {
    IconData? icon,
    bool spinner = false,
    required String text,
    required Color fg,
  }) =>
      Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            else if (icon != null)
              Icon(icon, size: 15, color: fg),
            const SizedBox(width: 7),
            Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        );
}
