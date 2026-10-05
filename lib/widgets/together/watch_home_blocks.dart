import 'package:flutter/material.dart';

import '../../models/reels_source.dart';
import '../../models/symbol_catalog.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../avatar_widget.dart';

/// Блоки экрана «Смотрим», вариант А макета «Афиша и плитки»
/// (https://claude.ai/artifact/NDn9aocymZmLRgQ6LH3omM, выбран 05.10.2026).
///
/// Кино — главная карточка заливкой темы с фото обоих и круглой кнопкой
/// запуска. Под ней плитки разной формы: высокая совместная лента, рядом игры
/// и тёмная плитка «С компьютера» с кодом комнаты. Плоско, без теней и
/// обводок; цвета — роли схемы и заливка темы ([AppTheme.fillColor]).

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
          var lo = max / 2, hi = max;
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

/// Заголовок экрана: крупно Unbounded, под ним строка.
class WatchLead extends StatelessWidget {
  const WatchLead({super.key, required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BalancedText(
            title,
            TextStyle(
              fontFamily: 'Unbounded',
              letterSpacing: 0,
              fontSize: 26,
              height: 1.08,
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Пилюля поверх цветной плитки: метка рекламы, замок Плюса.
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок узкой плитки: размер уменьшается, пока самое длинное слово не
/// встанет целиком. Unbounded широкий, и на 320 точках с крупным шрифтом
/// «Совместная» рвалась посреди слова.
///
/// Ширину даёт родитель ([maxWidth]): плитки стоят в `IntrinsicHeight`, а там
/// `LayoutBuilder` запрещён.
class _FitTitle extends StatelessWidget {
  const _FitTitle(this.text, this.style, this.maxWidth);

  final String text;
  final TextStyle style;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final max = maxWidth;
    if (max == null || max <= 0) return Text(text, style: style);
    final scaler = MediaQuery.textScalerOf(context);
    // Мерить тем же стилем, каким нарисует Text: он сливается с темой, а у M3
    // там разрядка 0.25 — без неё слово мерилось уже, чем выходило на экране.
    final full = DefaultTextStyle.of(context).style.merge(style);
    var size = full.fontSize ?? 15;
    final words = text.split(RegExp(r'\s+'));
    double widest(double s) {
      var w = 0.0;
      for (final word in words) {
        final tp = TextPainter(
          text: TextSpan(
            text: word,
            style: full.copyWith(fontSize: s),
          ),
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
    return Text(text, style: style.copyWith(fontSize: size));
  }
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

/// Главная карточка: смотреть кино с партнёром.
class WatchKinoCard extends StatelessWidget {
  const WatchKinoCard({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
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
  });

  final AppTheme theme;
  final String title;
  final String subtitle;

  /// «Ссылка, файл или Shorts» — слева от кнопки запуска.
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

  @override
  Widget build(BuildContext context) {
    final fill = theme.fillColor;
    final on = AppThemes.onColor(fill, mode: theme.brightness);
    Widget avatar(String uid, String url, String name) => Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      // Заглушка с буквой красится этим цветом: основной цвет темы совпал
      // бы с карточкой, и без фото аватарки не было бы видно.
      child: AvatarWidget(uid: uid, liveUrl: url, name: name, size: 42, primary: on, showFrame: false),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: partnerUid.isEmpty ? 48 : 82,
                      height: 48,
                      child: Stack(
                        children: [
                          avatar(myUid, myAvatar, myName),
                          if (partnerUid.isNotEmpty) Positioned(left: 34, child: avatar(partnerUid, partnerAvatar, partnerName)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: note == null
                            ? const SizedBox.shrink()
                            : _Chip(
                                icon: const IconData(0xea0b, fontFamily: SymbolCatalog.fontFamily),
                                label: note!,
                                fg: on,
                                bg: on.withValues(alpha: 0.24),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _BalancedText(title, _title(25, on).copyWith(height: 1.1), maxLines: 3),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 14, height: 1.45, color: on.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        hint,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          letterSpacing: 0,
                          fontSize: 13,
                          height: 1.45,
                          color: on.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: on, shape: BoxShape.circle),
                      child: Icon(const IconData(0xe037, fontFamily: SymbolCatalog.fontFamily), size: 36, color: fill),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Плитка-основа для блоков ниже главной карточки.
class _Tile extends StatelessWidget {
  const _Tile({required this.color, required this.child, this.onTap});

  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

/// Совместная лента: высокая плитка с иконками площадок.
class WatchReelsTile extends StatelessWidget {
  const WatchReelsTile({super.key, required this.title, required this.text, required this.plusLocked, this.onTap, this.titleWidth});

  /// Ширина под заголовок, см. [_FitTitle].
  final double? titleWidth;
  final String title;
  final String text;

  /// Чип «Togetherly+» с замком: ленту здесь можно только купить или ждать зова.
  final bool plusLocked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.tertiaryContainer;
    final fg = cs.onTertiaryContainer;
    // Иконки идут внахлёст: на узкой плитке нахлёст глубже, чем правый край.
    final room = titleWidth;
    final last = ReelsSource.values.length - 1;
    final logoStep = room == null || last <= 0 ? 24.0 : ((room - 34) / last).clamp(14.0, 24.0);
    return _Tile(
      color: bg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          // Отступ внутри детей, а не отдельной коробкой: spaceBetween делил бы
          // свободное место и на неё, и заголовок уезжал бы вниз от макета.
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FitTitle(title, _title(15.5, fg).copyWith(height: 1.15), titleWidth),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 13, height: 1.45, color: fg.withValues(alpha: 0.86)),
                ),
              ],
            ),
          ),
          if (plusLocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _Chip(
                icon: const IconData(0xe899, fontFamily: SymbolCatalog.fontFamily),
                label: 'Togetherly+',
                fg: fg,
                bg: fg.withValues(alpha: 0.12),
              ),
            )
          else
            const SizedBox(height: 0),
        ],
      ),
    );
  }
}

/// Играть вместе.
class WatchGamesTile extends StatelessWidget {
  const WatchGamesTile({super.key, required this.title, required this.text, required this.onTap, this.titleWidth});

  /// Ширина под заголовок, см. [_FitTitle].
  final double? titleWidth;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSecondaryContainer;
    return _Tile(
      color: cs.secondaryContainer,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(const IconData(0xea28, fontFamily: SymbolCatalog.fontFamily), color: fg, size: 24),
          ),
          const SizedBox(height: 8),
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
          Text(
            text,
            style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 12.5, height: 1.45, color: fg.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// С компьютера: тёмная плитка с кодом комнаты, «скопировать» и «открыть сайт».
/// Сайт и код — один путь (партнёр смотрит в браузере), поэтому одна плитка.
class WatchComputerTile extends StatelessWidget {
  const WatchComputerTile({
    super.key,
    required this.code,
    required this.loading,
    required this.onCopy,
    required this.onOpenSite,
    this.onRetry,
  });

  final String code;
  final bool loading;
  final VoidCallback onCopy;
  final VoidCallback onOpenSite;

  /// Код так и не дали — спросить заново.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final cs = Theme.of(context).colorScheme;
    final bg = cs.inverseSurface;
    final fg = cs.onInverseSurface;
    Widget action(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: Material(
        color: fg.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 19, color: fg)),
        ),
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
        child: Text(code, style: _title(19, fg).copyWith(letterSpacing: 0.4)),
      );
    }
    return _Tile(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.watchFromComputer,
            style: TextStyle(fontFamily: 'Onest', letterSpacing: 0, fontSize: 12, color: fg.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
          codeText,
          const SizedBox(height: 8),
          Row(
            children: [
              action(const IconData(0xe14d, fontFamily: SymbolCatalog.fontFamily), s.copyLink, code.isEmpty ? null : onCopy),
              const SizedBox(width: 8),
              action(const IconData(0xe89e, fontFamily: SymbolCatalog.fontFamily), s.watchOpenOnSite, code.isEmpty ? null : onOpenSite),
            ],
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
  final Widget computer;

  static const double _gap = 10;
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
                    Expanded(child: computer),
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
                ? [Expanded(child: games(title)), const SizedBox(width: _gap), Expanded(child: computer)]
                : [
                    Expanded(child: reelsTile),
                    const SizedBox(width: _gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          games(title),
                          const SizedBox(height: _gap),
                          computer,
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
