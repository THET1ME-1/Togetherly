import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dict_strings.dart' show trKey;
import '../services/wallet_teaser.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import '../widgets/common/m3_loading.dart';

/// Стена ожидания Togetherly Wallet, оформленная чеком.
///
/// Открывается кнопкой с купюрами на главной, пока Wallet не вышел. Вариант «Чек»
/// выбран человеком из трёх макетов 18.09.2026 (артефакт «Стена ожидания
/// Wallet»): чек повторяет квитанцию с баннера Wallet в Google Play, строки —
/// что умеет приложение, итог — сколько людей ждут. После нажатия «Добавить в
/// ожидание» на чек ложится печать с номером места в очереди.
///
/// Число и место отдаёт сервер (`/api/wallet/waitlist`). Если по дороге
/// выяснится, что Wallet уже вышел, стена закрывается и открывает его сама:
/// кэш флага на главной мог отстать.
class WalletWaitScreen extends StatefulWidget {
  const WalletWaitScreen({
    super.key,
    required this.theme,
    this.load,
    this.join,
    this.openWallet,
  });

  final AppTheme theme;

  /// Подмена сервера в тестах. По умолчанию — [WalletTeaser].
  final Future<WaitlistState?> Function()? load;
  final Future<WaitlistState?> Function()? join;
  final Future<bool> Function()? openWallet;

  @override
  State<WalletWaitScreen> createState() => _WalletWaitScreenState();
}

/// Число с разрядами через неразрывный пробел: «2 418».
@visibleForTesting
String groupDigits(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('\u00A0');
    out.write(s[i]);
  }
  return out.toString();
}

class _WalletWaitScreenState extends State<WalletWaitScreen> {
  WaitlistState? _state;
  bool _loading = true;
  bool _busy = false;

  /// Растёт на каждое удачное нажатие — по нему взлетает «+1».
  int _plusTick = 0;

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await (widget.load ?? WalletTeaser.fetch)();
    if (!mounted) return;
    if (s != null && s.links.releasedFor(isIOS: _isIOS)) {
      final open = widget.openWallet ?? WalletTeaser.open;
      Navigator.of(context).maybePop();
      await open();
      return;
    }
    setState(() {
      _state = s;
      _loading = false;
    });
  }

  Future<void> _onJoin() async {
    if (_busy) return;
    if (_state?.joined == true) {
      HapticFeedback.selectionClick();
      return;
    }
    setState(() => _busy = true);
    final s = await (widget.join ?? WalletTeaser.join)();
    if (!mounted) return;
    if (s == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trKey('walletJoinFailed'))),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _state = s;
      _busy = false;
      _plusTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final scheme = ProfileTheme.schemeFor(t);
    final fill = t.fillColor;
    final onFill = AppThemes.onColor(fill, mode: t.brightness);
    final joined = _state?.joined == true;
    final still = MediaQuery.of(context).disableAnimations;

    return Theme(
      data: ProfileTheme.data(scheme),
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHigh,
                        foregroundColor: scheme.onSurface,
                        fixedSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        trKey('walletSoon').toUpperCase(),
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Column(
                    children: [
                      _Receipt(
                        scheme: scheme,
                        art: t.isDark
                            ? scheme.primaryContainer
                            : scheme.secondaryContainer,
                        stamp: fill,
                        state: _state,
                        loading: _loading,
                        plusTick: _plusTick,
                        still: still,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        trKey('walletFoot'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 13,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        key: const ValueKey('wallet-join'),
                        onPressed: _onJoin,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              joined ? scheme.secondaryContainer : fill,
                          foregroundColor:
                              joined ? scheme.onSecondaryContainer : onFill,
                          shape: const StadiumBorder(),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontFamily: ProfileTheme.bodyFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: _busy
                            ? M3Loading(color: onFill, size: 22)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (joined) ...[
                                    const Icon(Icons.check_rounded, size: 20),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Text(
                                      trKey(joined
                                          ? 'walletJoined'
                                          : 'walletJoin'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      trKey(joined ? 'walletHintAfter' : 'walletHintBefore'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 13,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сам чек: шапка с кошельком, строки возможностей, итог и печать.
class _Receipt extends StatelessWidget {
  const _Receipt({
    required this.scheme,
    required this.art,
    required this.stamp,
    required this.state,
    required this.loading,
    required this.plusTick,
    required this.still,
  });

  final ColorScheme scheme;
  final Color art;
  final Color stamp;
  final WaitlistState? state;
  final bool loading;
  final int plusTick;
  final bool still;

  static const _rows = [
    ('walletRowBudget', 'walletRowBudgetValue'),
    ('walletRowPersonal', 'walletRowPersonalValue'),
    ('walletRowSplit', 'walletRowSplitValue'),
    ('walletRowGoals', 'walletRowGoalsValue'),
    ('walletRowBank', 'walletRowBankValue'),
    ('walletRowChat', 'walletRowChatValue'),
  ];

  @override
  Widget build(BuildContext context) {
    final paper = scheme.surfaceContainer;
    final ink = scheme.onSurface;
    final soft = scheme.onSurfaceVariant;
    final line = scheme.outlineVariant;
    final joined = state?.joined == true;

    return ClipPath(
      clipper: const ReceiptEdgeClipper(),
      child: Container(
        color: paper,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(color: art, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Transform.rotate(
                    angle: -6 * math.pi / 180,
                    child: Image.asset(
                      'assets/images/logo/wallet_teaser.webp',
                      width: 104,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'TOGETHERLY WALLET',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.displayFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  trKey('walletTagline'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ProfileTheme.bodyFont,
                    fontSize: 14,
                    color: soft,
                  ),
                ),
                _DashRule(color: line),
                for (final (k, v) in _rows)
                  ReceiptLine(
                    label: trKey(k),
                    value: trKey(v),
                    ink: ink,
                    soft: soft,
                    dots: line,
                  ),
                _DashRule(color: line),
                _Total(
                  label: trKey('walletWaitingTotal'),
                  count: state?.count,
                  loading: loading,
                  ink: ink,
                  soft: soft,
                  accent: stamp,
                  plusTick: plusTick,
                  still: still,
                ),
              ],
            ),
            Positioned(
              right: -6,
              top: 214,
              child: IgnorePointer(
                child: _Stamp(
                  shown: joined,
                  place: state?.place ?? 0,
                  color: stamp,
                  paper: paper,
                  still: still,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижний край чека: полукруглые выемки, как у отрывной ленты.
///
/// Узор центрируется по ширине, чтобы крайние выемки не обрезались половиной.
class ReceiptEdgeClipper extends CustomClipper<Path> {
  const ReceiptEdgeClipper({this.period = 22, this.radius = 9, this.corner = 28});

  final double period;
  final double radius;
  final double corner;

  @override
  Path getClip(Size size) {
    final body = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: Radius.circular(corner),
        topRight: Radius.circular(corner),
      ));
    final count = (size.width / period).floor();
    if (count < 1) return body;
    final start = (size.width - count * period) / 2 + period / 2;
    final notches = Path();
    for (var i = 0; i < count; i++) {
      notches.addOval(Rect.fromCircle(
          center: Offset(start + i * period, size.height), radius: radius));
    }
    return Path.combine(PathOperation.difference, body, notches);
  }

  @override
  bool shouldReclip(covariant ReceiptEdgeClipper old) =>
      old.period != period || old.radius != radius || old.corner != corner;
}

/// Пунктир между разделами чека.
class _DashRule extends StatelessWidget {
  const _DashRule({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: CustomPaint(
        size: const Size(double.infinity, 2),
        painter: _DashPainter(color),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 11) {
      canvas.drawLine(Offset(x, 1), Offset(math.min(x + 6, size.width), 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// Строка чека: название слева, значение справа, точки между ними.
///
/// Если на узком экране при крупном шрифте строка не помещается, значение
/// уходит на вторую строку и прижимается вправо, а точки ведут к нему уже
/// там — обрезанная подпись в чеке читалась бы поломкой.
class ReceiptLine extends StatelessWidget {
  const ReceiptLine({
    super.key,
    required this.label,
    required this.value,
    required this.ink,
    required this.soft,
    required this.dots,
  });

  final String label;
  final String value;
  final Color ink;
  final Color soft;
  final Color dots;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontFamily: ProfileTheme.bodyFont,
      fontSize: 14.5,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: ink,
    );
    final valueStyle = labelStyle.copyWith(fontWeight: FontWeight.w400, color: soft);
    final scaler = MediaQuery.textScalerOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(builder: (context, box) {
        double measure(String s, TextStyle st) {
          final tp = TextPainter(
            text: TextSpan(text: s, style: st),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        final fits = measure(label, labelStyle) +
                measure(value, valueStyle) +
                28 <=
            box.maxWidth;
        final leader = Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: CustomPaint(
              size: const Size(double.infinity, 4),
              painter: _DotsPainter(dots),
            ),
          ),
        );
        if (fits) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label, style: labelStyle),
              leader,
              Text(value, style: valueStyle),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: labelStyle),
            Row(
              children: [
                leader,
                Flexible(
                  flex: 3,
                  child: Text(value, style: valueStyle, textAlign: TextAlign.right),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final y = size.height / 2 + 4;
    for (double x = 1.2; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x, y), 1.2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}

/// Итог чека: «Ждут выхода» и крупное число, которое прокручивает цифры.
class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.count,
    required this.loading,
    required this.ink,
    required this.soft,
    required this.accent,
    required this.plusTick,
    required this.still,
  });

  final String label;
  final int? count;
  final bool loading;
  final Color ink;
  final Color soft;
  final Color accent;
  final int plusTick;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final numStyle = TextStyle(
      fontFamily: ProfileTheme.displayFont,
      fontSize: 44,
      height: 1.05,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final Widget number;
    if (count != null) {
      number = RollingNumber(value: count!, style: numStyle, still: still);
    } else if (loading) {
      number = SizedBox(height: 46, child: M3Loading(color: accent, size: 40));
    } else {
      number = Text('—', style: numStyle.copyWith(color: soft));
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Число держит до двух третей ширины и дальше ужимается: «100 000» при
        // крупном шрифте на 320 dp иначе выдавило бы подпись за край.
        LayoutBuilder(
          builder: (context, box) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 2,
                    style: TextStyle(
                      fontFamily: ProfileTheme.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: soft,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 2 / 3),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: number,
                ),
              ),
            ],
          ),
        ),
        if (plusTick > 0 && !still)
          Positioned(
            right: 0,
            top: -22,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(plusTick),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              builder: (context, v, child) {
                final rise = const Cubic(0.05, 0.7, 0.1, 1).transform(v);
                final alpha = v < 0.2 ? v / 0.2 : 1 - (v - 0.2) / 0.8;
                return Opacity(
                  opacity: alpha.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 8 - 34 * rise),
                    child: child,
                  ),
                );
              },
              child: Text(
                '+1',
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Число, у которого сменившиеся цифры уезжают вверх, а новые приходят снизу.
///
/// Цифры привязаны к разряду справа, поэтому 9 999 → 10 000 тоже прокручивается
/// по месту, а не прыгает всей строкой.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.still = false,
  });

  final int value;
  final TextStyle style;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final text = groupDigits(value);
    final chars = text.split('');
    final gap = (style.fontSize ?? 16) * 0.26;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chars.length; i++)
            if (chars[i] == '\u00A0')
              SizedBox(width: gap)
            else
              ClipRect(
                child: AnimatedSwitcher(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 550),
                  switchInCurve: const Cubic(0.2, 0, 0, 1),
                  switchOutCurve: const Cubic(0.2, 0, 0, 1),
                  transitionBuilder: (child, animation) {
                    final incoming =
                        child.key == ValueKey('${chars.length - i}:${chars[i]}');
                    final slide = Tween<Offset>(
                      begin: Offset(0, incoming ? 1 : -1),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(position: slide, child: child);
                  },
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [...previous, ?current],
                  ),
                  child: Text(
                    chars[i],
                    key: ValueKey('${chars.length - i}:${chars[i]}'),
                    style: style,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Печать «Ваше место № N в очереди». Ложится с высоты: масштаб 1,6 → 1.
class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.shown,
    required this.place,
    required this.color,
    required this.paper,
    required this.still,
  });

  final bool shown;
  final int place;
  final Color color;
  final Color paper;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(
      fontFamily: ProfileTheme.bodyFont,
      fontSize: 10,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: color,
    );
    final big = TextStyle(
      fontFamily: ProfileTheme.displayFont,
      fontSize: 20,
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: color,
    );
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      child: AnimatedScale(
        scale: shown ? 1 : 1.6,
        duration: still ? Duration.zero : const Duration(milliseconds: 500),
        curve: const Cubic(0.05, 0.7, 0.1, 1),
        child: Transform.rotate(
          angle: -14 * math.pi / 180,
          child: Container(
            width: 124,
            height: 124,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: paper.withValues(alpha: 0.72),
              border: Border.all(color: color, width: 3),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(trKey('walletStampTop').toUpperCase(), style: small),
                ),
                const SizedBox(height: 6),
                // Знак и число отдельными словами: неразрывный пробел в
                // Unbounded почти нулевой, и на эмуляторе печать читалась
                // «№1» впритык (18.09.2026).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('№', style: big),
                      const SizedBox(width: 5),
                      Text(groupDigits(place), style: big),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child:
                      Text(trKey('walletStampBottom').toUpperCase(), style: small),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
