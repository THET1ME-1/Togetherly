import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/reels_source.dart';
import '../../models/symbol_catalog.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../avatar_widget.dart';
import 'watch_pattern.dart';

/// Блоки экрана «Смотрим», вариант А макета «Афиша и плитки»
/// (https://claude.ai/artifact/NDn9aocymZmLRgQ6LH3omM, выбран 05.10.2026),
/// с узорами «по углам» и откликом на нажатие из макета
/// https://claude.ai/artifact/Ji4675yhiELRjRu3YSK5sv.
///
/// Кино — главная карточка заливкой темы с фото обоих и круглой кнопкой
/// запуска. Под ней плитки: высокая совместная лента, рядом игры и тёмная
/// плитка «С компьютера» с кодом комнаты. Плоско, без теней и обводок; цвета —
/// роли схемы и заливка темы ([AppTheme.fillColor]).
///
/// Отступы — одна сетка: поле 20 у кино и 16 у плиток, промежутки 8 (подпись
/// под заголовком) и 16 (между группами). Узор занимает свой угол и ничего не
/// сдвигает.

/// Заголовок с ровными строками, как `text-wrap: balance` в макете: ширина
/// ужимается, пока число строк не растёт. Иначе «Одно кино на / двоих»
/// оставляет одно слово висеть внизу.
class _BalancedText extends StatelessWidget {
  const _BalancedText(this.text, this.style, {this.maxLines});

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final max = c.maxWidth;
        TextPainter lay(double w) => TextPainter(
          text: TextSpan(text: text, style: merged),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: maxLines,
        )..layout(maxWidth: w);
        final lines = lay(max).computeLineMetrics().length;
        var width = max;
        if (max.isFinite && lines > 1) {
          // Уже самого длинного слова не ужимать: число строк при этом то же,
          // а слово рвётся посреди («Смотре / ть»).
          var widest = 0.0;
          for (final word in text.split(RegExp(r'\s+'))) {
            final tp = TextPainter(
              text: TextSpan(text: word, style: merged),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (tp.width > widest) widest = tp.width;
          }
          var lo = math.min(math.max(max / 2, widest + 1), max), hi = max;
          for (var i = 0; i < 12; i++) {
            final mid = (lo + hi) / 2;
            final p = lay(mid);
            if (p.computeLineMetrics().length > lines || p.didExceedMaxLines) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          width = hi + 1;
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width.clamp(0, max),
            child: Text(text, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

/// Заголовок экрана: крупно Unbounded. Строку-пояснение под ним убрали
/// (05.10.2026): «пауза у одного, пауза у обоих» и так понятно.
class WatchLead extends StatelessWidget {
  const WatchLead({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: _BalancedText(
        title,
        TextStyle(
          fontFamily: 'Unbounded',
          letterSpacing: 0,
          fontSize: 25,
          height: 1.1,
          fontWeight: FontWeight.w800,
          fontVariations: const [FontVariation('wght', 800)],
          color: cs.onSurface,
        ),
      ),
    );
  }
}

/// Пилюля поверх цветной плитки: метка рекламы.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.fg, required this.bg});

  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кегль, при котором самое длинное слово [text] встаёт в [maxWidth] целиком.
/// Unbounded широкий, и на 320 точках с крупным шрифтом «Совместная» и
/// «Смотреть» рвались посреди слова.
double _fitSize(BuildContext context, String text, TextStyle style, double? maxWidth) {
  // Мерить тем же стилем, каким нарисует Text: он сливается с темой, а у M3
  // там разрядка 0.25 — без неё слово мерилось уже, чем выходило на экране.
  final full = DefaultTextStyle.of(context).style.merge(style);
  var size = full.fontSize ?? 15;
  final max = maxWidth;
  if (max == null || max <= 0) return size;
  final scaler = MediaQuery.textScalerOf(context);
  final words = text.split(RegExp(r'\s+'));
  double widest(double s) {
    var w = 0.0;
    for (final word in words) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: full.copyWith(fontSize: s)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > w) w = tp.width;
    }
    return w;
  }

  while (size > 10 && widest(size) > max) {
    size -= 0.5;
  }
  return size;
}

/// Заголовок узкой плитки, см. [_fitSize]. Ширину даёт родитель
/// ([maxWidth]): плитки стоят в `IntrinsicHeight`, а там `LayoutBuilder`
/// запрещён.
class _FitTitle extends StatelessWidget {
  const _FitTitle(this.text, this.style, this.maxWidth);

  final String text;
  final TextStyle style;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: style.copyWith(fontSize: _fitSize(context, text, style, maxWidth)));
}

TextStyle _title(double size, Color color) => TextStyle(
  fontFamily: 'Unbounded',
  letterSpacing: 0,
  fontSize: size,
  height: 1.12,
  fontWeight: FontWeight.w800,
  fontVariations: const [FontVariation('wght', 800)],
  color: color,
);

TextStyle _body(double size, Color color) =>
    TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: size, height: 1.45, color: color);

/// Главная карточка: смотреть кино с партнёром. Нажимается вся; откликается
/// кнопка «играть». Узор — колонка кино справа во всю высоту.
class WatchKinoCard extends StatelessWidget {
  const WatchKinoCard({
    super.key,
    required this.theme,
    required this.title,
    required this.hint,
    required this.myUid,
    required this.myAvatar,
    required this.myName,
    required this.partnerUid,
    required this.partnerAvatar,
    required this.partnerName,
    this.note,
    required this.enabled,
    required this.onTap,
    this.seed = 1,
  });

  final AppTheme theme;
  final String title;

  /// «Ссылка, файл или Shorts» — под заголовком.
  final String hint;
  final String myUid;
  final String myAvatar;
  final String myName;
  final String partnerUid;
  final String partnerAvatar;
  final String partnerName;

  /// «После короткой рекламы» — у купившего Плюс её нет.
  final String? note;
  final bool enabled;
  final VoidCallback onTap;

  /// Число раскладки узора, см. [watchPatternSeed].
  final int seed;

  /// Колонка узора справа и поле под ней у текста.
  static const double _patternWidth = 120;
  static const double _pad = 20;
  static const double _play = 64;

  @override
  Widget build(BuildContext context) {
    final fill = theme.fillColor;
    final on = AppThemes.onColor(fill, mode: theme.brightness);
    Widget avatar(String uid, String url, String name) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      // Заглушка с буквой красится этим цветом: основной цвет темы совпал
      // бы с карточкой, и без фото аватарки не было бы видно.
      child: AvatarWidget(uid: uid, liveUrl: url, name: name, size: 46, primary: on, showFrame: false),
    );
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(_pad, _pad, _patternWidth + 16, _pad + _play + 16),
      child: LayoutBuilder(
        builder: (context, c) {
          final titleStyle = _title(21, on);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: partnerUid.isEmpty ? 52 : 88,
                height: 52,
                child: Stack(
                  children: [
                    avatar(myUid, myAvatar, myName),
                    if (partnerUid.isNotEmpty) Positioned(left: 36, child: avatar(partnerUid, partnerAvatar, partnerName)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _BalancedText(
                title,
                titleStyle.copyWith(fontSize: _fitSize(context, title, titleStyle, c.maxWidth)),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Text(hint, style: _body(13, on.withValues(alpha: 0.9))),
              if (note != null) ...[
                const SizedBox(height: 8),
                _Chip(
                  icon: const IconData(0xea0b, fontFamily: SymbolCatalog.fontFamily),
                  label: note!,
                  fg: on,
                  bg: on.withValues(alpha: 0.24),
                ),
              ],
            ],
          );
        },
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: WatchFx(
        color: fill,
        radius: 32,
        rippleColor: watchRippleColor(fill, on, .3),
        onTap: enabled ? onTap : null,
        focusId: 'play',
        after: WatchFxAfter.spin,
        semanticLabel: title,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: _patternWidth,
              child: WatchPattern(motifs: WatchMotifs.kino, seed: seed, tones: watchPatternTones(fill), cols: 3, rows: 8),
            ),
            ConstrainedBox(constraints: const BoxConstraints(minHeight: 272), child: content),
            Positioned(
              left: _pad,
              bottom: _pad,
              child: WatchFxButton(
                id: 'play',
                size: _play,
                color: on,
                icon: const IconData(0xe037, fontFamily: SymbolCatalog.fontFamily),
                iconSize: 36,
                iconColor: fill,
                spinColor: fill,
                spinInset: 20,
                spinWidth: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Совместная лента: узор сверху, под ним иконки площадок, название и
/// описание. Платная — плашка Togetherly+ при нажатии ведёт к Плюсу.
class WatchReelsTile extends StatelessWidget {
  const WatchReelsTile({
    super.key,
    required this.title,
    required this.text,
    required this.plusLocked,
    this.onTap,
    this.titleWidth,
    this.seed = 1,
  });

  /// Ширина под заголовок, см. [_FitTitle].
  final double? titleWidth;
  final String title;
  final String text;

  /// Чип «Togetherly+» с замком: ленту здесь можно только купить или ждать зова.
  final bool plusLocked;
  final VoidCallback? onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.tertiaryContainer;
    final fg = cs.onTertiaryContainer;
    // Иконки идут внахлёст: на узкой плитке нахлёст глубже, чем правый край.
    final room = titleWidth;
    final last = ReelsSource.values.length - 1;
    final logoStep = room == null || last <= 0 ? 24.0 : ((room - 34) / last).clamp(14.0, 24.0);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 104, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Stack(
              children: [
                for (final (i, s) in ReelsSource.values.indexed)
                  Positioned(
                    left: i * logoStep,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(s.icon, width: 30, height: 30, cacheWidth: 90),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _FitTitle(title, _title(15.5, fg).copyWith(height: 1.15), titleWidth),
          const SizedBox(height: 8),
          Text(text, style: _body(13, fg.withValues(alpha: 0.86))),
          if (plusLocked) ...[
            const SizedBox(height: 16),
            WatchPlusChip(id: 'reels', label: 'Togetherly+', fg: fg, bg: bg),
          ],
        ],
      ),
    );
    return WatchFx(
      color: bg,
      radius: 28,
      pressedScale: .97,
      rippleColor: watchRippleColor(bg, fg, .45),
      onTap: onTap,
      focusId: 'reels',
      after: plusLocked ? WatchFxAfter.plus : WatchFxAfter.none,
      semanticLabel: title,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: WatchPattern(motifs: WatchMotifs.reels, seed: seed + 10, tones: watchPatternTones(bg), cols: 4, rows: 3),
          ),
          body,
        ],
      ),
    );
  }
}

/// Играть вместе: откроется сайт с играми. Узор — квадрат в правом верхнем
/// углу напротив значка.
class WatchGamesTile extends StatelessWidget {
  const WatchGamesTile({super.key, required this.title, required this.text, required this.onTap, this.titleWidth, this.seed = 1});

  /// Ширина под заголовок, см. [_FitTitle].
  final double? titleWidth;
  final String title;
  final String text;
  final VoidCallback onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.secondaryContainer;
    final fg = cs.onSecondaryContainer;
    return WatchFx(
      color: bg,
      radius: 28,
      pressedScale: .97,
      rippleColor: watchRippleColor(bg, fg, .45),
      onTap: onTap,
      focusId: 'games',
      after: WatchFxAfter.spin,
      semanticLabel: title,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            top: 0,
            right: 0,
            width: 72,
            height: 72,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28)),
              child: WatchPattern(motifs: WatchMotifs.games, seed: seed + 20, tones: watchPatternTones(bg), cols: 2, rows: 2, cell: 36),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                WatchFxButton(
                  id: 'games',
                  size: 44,
                  color: fg.withValues(alpha: 0.12),
                  icon: const IconData(0xea28, fontFamily: SymbolCatalog.fontFamily),
                  iconSize: 22,
                  iconColor: fg,
                  spinColor: fg,
                ),
                const SizedBox(height: 16),
                _FitTitle(
                  title,
                  TextStyle(
                    fontFamily: 'Unbounded',
                    letterSpacing: 0,
                    fontSize: 14.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    color: fg,
                  ),
                  titleWidth,
                ),
                const SizedBox(height: 8),
                Text(text, style: _body(12.5, fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// С компьютера: тёмная плитка с кодом комнаты, «скопировать» и «открыть сайт».
/// Сайт и код — один путь (партнёр смотрит в браузере), поэтому одна плитка.
/// Узор — полоска клавиш у правого края.
class WatchComputerTile extends StatelessWidget {
  const WatchComputerTile({
    super.key,
    required this.code,
    required this.loading,
    required this.onCopy,
    required this.onOpenSite,
    this.onRetry,
    this.seed = 1,
    this.titleWidth,
  });

  /// Ширина плитки без полей, см. [_FitTitle]; подписи остаётся меньше на
  /// полоску узора.
  final double? titleWidth;
  final String code;
  final bool loading;
  final VoidCallback onCopy;
  final VoidCallback onOpenSite;

  /// Код так и не дали — спросить заново.
  final VoidCallback? onRetry;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final bg = cs.inverseSurface;
    final fg = cs.onInverseSurface;
    // Полоска узора 40 точек; в тесной плитке (320 точек, крупный шрифт) — 24,
    // иначе «компьютера» не встаёт в строку и самым мелким кеглем.
    final strip = titleWidth != null && titleWidth! < 110 ? 24.0 : 40.0;
    final labelWidth = titleWidth == null ? null : titleWidth! - strip;
    Widget action(Object id, IconData icon, String tip, WatchFxAfter after, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: WatchFxButton(
        id: id,
        size: 40,
        color: fg.withValues(alpha: 0.14),
        icon: icon,
        iconSize: 19,
        iconColor: fg,
        spinColor: fg,
        after: after,
        selfTap: true,
        onTap: onTap,
        tooltip: tip,
      ),
    );
    final Widget codeText;
    if (loading) {
      codeText = Text('…', style: _title(19, fg));
    } else if (code.isEmpty) {
      // Код не дали — словами и с повтором, а не молчаливым прочерком.
      codeText = InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(const IconData(0xe5d5, fontFamily: SymbolCatalog.fontFamily), size: 18, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                s.watchCodeRetry,
                style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 14, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
          ],
        ),
      );
    } else {
      codeText = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(code, style: _title(19, fg).copyWith(height: 1, letterSpacing: 0.4)),
      );
    }
    return WatchFx(
      color: bg,
      radius: 28,
      rippleColor: watchRippleColor(bg, fg, .45),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: strip,
            child: WatchPattern(motifs: WatchMotifs.computer, seed: seed + 30, tones: watchPatternTones(bg), cols: 1, rows: 4),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16 + strip, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _FitTitle(s.watchFromComputer, _body(12, fg.withValues(alpha: 0.8)), labelWidth),
                const SizedBox(height: 8),
                codeText,
                const SizedBox(height: 16),
                // Wrap, а не Row: на 320 точках с крупным шрифтом две кнопки
                // рядом в колонку не входят и встают друг под другом.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    action('copy', const IconData(0xe14d, fontFamily: SymbolCatalog.fontFamily), s.copyLink, WatchFxAfter.check,
                        code.isEmpty ? null : onCopy),
                    action('open', const IconData(0xe89e, fontFamily: SymbolCatalog.fontFamily), s.watchOpenOnSite, WatchFxAfter.spin,
                        code.isEmpty ? null : onOpenSite),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плитки под главной карточкой: слева высокая лента, справа игры и вход с
/// компьютера; без ленты — игры и компьютер рядом. Высоту колонок выравнивает
/// `IntrinsicHeight`, а ширину под заголовки считает [LayoutBuilder] снаружи
/// него — внутри он запрещён.
class WatchBento extends StatelessWidget {
  const WatchBento({super.key, this.reels, required this.games, required this.computer});

  /// null — ленты на этом телефоне нет.
  final Widget Function(double titleWidth)? reels;
  final Widget Function(double titleWidth) games;
  final Widget Function(double titleWidth) computer;

  static const double _gap = 8;
  static const double _pad = 16;

  /// Половина ряда в точках при шрифте 1.0, ниже которой ленте тесно рядом с
  /// колонкой: на 320 точках «Совместная» не встаёт и самым мелким кеглем.
  static const double _sideBySideMin = 150;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, c) {
        final half = (c.maxWidth - _gap) / 2;
        final title = half - _pad * 2;
        if (reels != null && half / scale < _sideBySideMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              reels!(c.maxWidth - _pad * 2),
              const SizedBox(height: _gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: games(title)),
                    const SizedBox(width: _gap),
                    Expanded(child: computer(title)),
                  ],
                ),
              ),
            ],
          );
        }
        final reelsTile = reels?.call(title);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: reelsTile == null
                ? [Expanded(child: games(title)), const SizedBox(width: _gap), Expanded(child: computer(title))]
                : [
                    Expanded(child: reelsTile),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: games(title)),
                          const SizedBox(height: _gap),
                          computer(title),
                        ],
                      ),
                    ),
                  ],
          ),
        );
      },
    );
  }
}

/// Заголовок раздела со счётчиком.
class WatchSectionHeader extends StatelessWidget {
  const WatchSectionHeader({super.key, required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Unbounded',
              letterSpacing: 0,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
              color: cs.onSurface,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 26),
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(999)),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Onest',
                  letterSpacing: 0,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
