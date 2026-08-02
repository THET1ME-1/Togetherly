import 'package:flutter/material.dart';

import '../../models/mascot_anim.dart';
import '../../models/mascot_sleep.dart';
import '../../models/user_data.dart';
import '../../services/catalog_service.dart';
import '../../services/level_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import '../app_sheet.dart';
import 'pixel_mascot_view.dart';

/// Лист «Сон маскотов»: у каждого персонажа своё время ночной сцены.
///
/// Показываются только открытые персонажи, у которых ночь вообще нарисована.
/// Настраивать сон тому, кого у тебя нет, незачем, а список из одних замков
/// выглядел бы витриной, а не настройкой.
Future<void> showMascotSleepSheet(
  BuildContext context, {
  required AppTheme theme,
  required UserData user,
}) {
  // Тему снимаем ДО открытия листа: он живёт в дереве навигатора и переживает
  // экран, а обращение к состоянию мёртвого экрана уже давало падения.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final ru = LocaleService.instance.isRussian;

  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => _MascotSleepBody(scheme: scheme, ru: ru, user: user),
  );
}

/// Персонажи с ночной сценой, доступные этому человеку.
List<MascotAnim> nightCapableMascots() {
  final level = LevelService.instance.level;
  final list = CatalogService.instance.animated
      .where((a) => a.nightIdle.isNotEmpty)
      .where((a) => a.unlock.isUnlocked(level: level, owned: false))
      .toList();
  list.sort((a, b) => a.nameRu.compareTo(b.nameRu));
  return list;
}

class _MascotSleepBody extends StatefulWidget {
  const _MascotSleepBody({
    required this.scheme,
    required this.ru,
    required this.user,
  });

  final ColorScheme scheme;
  final bool ru;
  final UserData user;

  @override
  State<_MascotSleepBody> createState() => _MascotSleepBodyState();
}

class _MascotSleepBodyState extends State<_MascotSleepBody> {
  late final List<MascotAnim> _mascots = nightCapableMascots();

  ColorScheme get _scheme => widget.scheme;
  AppStrings get _s => LocaleService.instance.strings;

  Future<void> _pick(MascotAnim anim, {required bool start}) async {
    final now = widget.user.sleepOf(anim.id);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: start ? now.fromHour : now.toHour,
        minute: start ? now.fromMinute : now.toMinute,
      ),
      helpText: start ? _s.mascotSleepFrom : _s.mascotSleepTo,
    );
    if (picked == null) return;

    final minutes = picked.hour * 60 + picked.minute;
    await widget.user.setMascotSleep(
      anim.id,
      start ? now.copyWith(from: minutes) : now.copyWith(to: minutes),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggle(MascotAnim anim, bool value) async {
    final now = widget.user.sleepOf(anim.id);
    await widget.user.setMascotSleep(anim.id, now.copyWith(enabled: value));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: _s.mascotSleepTitle,
      child: _mascots.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Text(
                _s.mascotSleepEmpty,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  height: 1.4,
                  color: _scheme.onSurfaceVariant,
                ),
              ),
            )
          : Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: _mascots.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _MascotSleepCard(
                  anim: _mascots[i],
                  window: widget.user.sleepOf(_mascots[i].id),
                  scheme: _scheme,
                  ru: widget.ru,
                  onPickStart: () => _pick(_mascots[i], start: true),
                  onPickEnd: () => _pick(_mascots[i], start: false),
                  onToggle: (v) => _toggle(_mascots[i], v),
                ),
              ),
            ),
    );
  }
}

class _MascotSleepCard extends StatelessWidget {
  const _MascotSleepCard({
    required this.anim,
    required this.window,
    required this.scheme,
    required this.ru,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onToggle,
  });

  final MascotAnim anim;
  final SleepWindow window;
  final ColorScheme scheme;
  final bool ru;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final ValueChanged<bool> onToggle;

  String _time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.instance.strings;
    final from = _time(window.fromHour, window.fromMinute);
    final to = _time(window.toHour, window.toMinute);

    // Мигун в свои часы не спит, а разгорается: у него ночная строка не
    // «сон», и обещать людям сон было бы неправдой.
    final sleeps = anim.sleepsAtNight;
    final subtitle = window.enabled
        ? (sleeps ? s.mascotSleepRange(from, to) : s.mascotNightRange(from, to))
        : s.mascotSleepOff;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PixelMascotView(
                anim: anim,
                state: MascotAnimState.live,
                size: 44,
                sleep: window,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ru ? anim.nameRu : anim.nameEn,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: window.enabled, onChanged: onToggle),
            ],
          ),
          if (window.enabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: sleeps ? s.mascotSleepFrom : s.mascotSleepTo,
                    value: from,
                    scheme: scheme,
                    onTap: onPickStart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeButton(
                    label: sleeps ? s.mascotSleepTo : s.mascotSleepFrom,
                    value: to,
                    scheme: scheme,
                    onTap: onPickEnd,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Кнопка времени: подпись сверху, крупные цифры под ней.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.scheme,
    required this.onTap,
  });

  final String label;
  final String value;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11,
                  letterSpacing: 0.2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
