import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_data.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../theme/theme_scope.dart';
import 'login_screen.dart';
import 'setup_screen.dart';

/// Онбординг: три экрана, у каждого своя живая сцена.
///
/// Прежний собирался из значка на 120 пикселей и двух подписей, а цвета были
/// прибиты прямо в файле — фиолетовый, оранжевый, розовый, ни один из них к
/// теме приложения отношения не имел. Человек видел одно, а после входа
/// получал другое; тёмная тема онбординг не видела вовсе.
///
/// Теперь всё берётся из активной темы, а сцены рисуются кодом: ни Lottie, ни
/// Rive, ни файлов SVG — как маскоты и фоны холста.
class WelcomeScreen extends StatefulWidget {
  final UserData userData;
  const WelcomeScreen({super.key, required this.userData});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _ctrl = PageController();

  /// Дробная страница: по ней наливается кнопка и переползают точки, поэтому
  /// нужна не целая позиция, а положение между экранами.
  double _pos = 0;

  static const int _pages = 3;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final p = _ctrl.hasClients ? (_ctrl.page ?? 0) : 0.0;
      if ((p - _pos).abs() > 0.001) setState(() => _pos = p);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _page => _pos.round();
  bool get _last => _page >= _pages - 1;

  void _next() {
    if (_last) {
      _navigate(setup: true);
      return;
    }
    _ctrl.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: const Cubic(0.05, 0.7, 0.1, 1),
    );
  }

  Future<void> _navigate({required bool setup}) async {
    await widget.userData.markWelcomeSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => setup
            ? SetupScreen(userData: widget.userData)
            : LoginScreen(userData: widget.userData),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final theme = context.appTheme;
    final cs = ProfileTheme.schemeFor(theme);
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final titles = [
      s.welcomeSlide1Title,
      s.welcomeSlide2Title,
      s.welcomeSlide3Title,
    ];
    final subtitles = [
      s.welcomeSubtitle,
      s.welcomeFeatureMemories,
      s.welcomeFeatureMood,
    ];

    return Scaffold(
      backgroundColor: theme.bgGradient.first,
      body: Stack(
        children: [
          // Пятна тональных поверхностей: тот же приём, что на главной —
          // глубина цветом, без градиентов и теней.
          Positioned.fill(child: _Blobs(scheme: cs, still: still)),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: _last ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: TextButton(
                        onPressed: _last
                            ? null
                            : () => _ctrl.animateToPage(
                                  _pages - 1,
                                  duration: const Duration(milliseconds: 500),
                                  curve: const Cubic(0.05, 0.7, 0.1, 1),
                                ),
                        child: Text(
                          s.skip,
                          style: AppFonts.onest(
                              size: 14, weight: 600, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _ctrl,
                    children: [
                      _DuoScene(scheme: cs, still: still),
                      _MorphScene(scheme: cs, theme: theme, still: still),
                      _DialScene(scheme: cs, theme: theme, still: still),
                    ],
                  ),
                ),
                _Copy(
                  scheme: cs,
                  title: titles[_page],
                  subtitle: subtitles[_page],
                ),
                const SizedBox(height: 18),
                _Dots(scheme: cs, pos: _pos, count: _pages),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: _FillingButton(
                    // Кнопка наливается по мере пролистывания: к третьему
                    // экрану она залита целиком. Это и полоса прогресса, и
                    // обещание, что идти осталось недолго.
                    progress: ((_pos + 1) / _pages).clamp(0.0, 1.0),
                    theme: theme,
                    label: _last ? s.createAccount : s.welcomeNext,
                    onTap: _next,
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: AnimatedOpacity(
                    opacity: _last ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: TextButton(
                      onPressed:
                          _last ? () => _navigate(setup: false) : null,
                      child: Text(
                        s.alreadyHaveAccount,
                        style: AppFonts.onest(
                            size: 14, weight: 600, color: cs.primary),
                      ),
                    ),
                  ),
                ),
                Text(
                  s.privateSecure,
                  style: AppFonts.onest(
                    size: 10,
                    weight: 600,
                    letterSpacing: 2.4,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Подпись под сценой ───────────────────────────────────────────────────────

class _Copy extends StatelessWidget {
  const _Copy({
    required this.scheme,
    required this.title,
    required this.subtitle,
  });

  final ColorScheme scheme;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppFonts.unbounded(
              size: 28,
              weight: 800,
              height: 1.14,
              letterSpacing: -0.6,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppFonts.onest(
                size: 14, height: 1.45, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─── Точки ────────────────────────────────────────────────────────────────────

class _Dots extends StatelessWidget {
  const _Dots({required this.scheme, required this.pos, required this.count});

  final ColorScheme scheme;
  final double pos;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox(
              height: 7,
              // Ширина ползёт вместе с пальцем, а не прыгает на смене
              // страницы: активная точка тянется, соседняя сжимается.
              width: 7 + 17 * (1 - (pos - i).abs()).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(
                    scheme.outlineVariant,
                    scheme.primary,
                    (1 - (pos - i).abs()).clamp(0.0, 1.0),
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Кнопка, которая наливается ───────────────────────────────────────────────

class _FillingButton extends StatelessWidget {
  const _FillingButton({
    required this.progress,
    required this.theme,
    required this.label,
    required this.onTap,
  });

  final double progress;
  final AppTheme theme;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = theme.fillColor;
    final ink = AppThemes.onColor(fill, mode: theme.brightness);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Незалитая часть — тот же цвет вполсилы, а не серая подложка:
              // кнопка читается как одна вещь, просто наполненная не до конца.
              ColoredBox(color: fill.withValues(alpha: 0.34)),
              // Ширину считаем сами: `FractionallySizedBox` внутри Stack с
              // `StackFit.expand` растягивался на всю кнопку, и налитой части
              // видно не было вовсе.
              LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: const Cubic(0.05, 0.7, 0.1, 1),
                    width: c.maxWidth * progress,
                    color: fill,
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppFonts.onest(size: 16, weight: 700, color: ink),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 19, color: ink),
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

// ─── Фоновые пятна ────────────────────────────────────────────────────────────

class _Blobs extends StatefulWidget {
  const _Blobs({required this.scheme, required this.still});

  final ColorScheme scheme;
  final bool still;

  @override
  State<_Blobs> createState() => _BlobsState();
}

class _BlobsState extends State<_Blobs> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.still) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _BlobPainter(scheme: widget.scheme, t: _ctrl.value),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.scheme, required this.t});

  final ColorScheme scheme;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color, double phase) {
      final dx = math.sin((t + phase) * math.pi * 2) * 12;
      final dy = math.cos((t + phase) * math.pi * 2) * 9;
      canvas.drawCircle(c + Offset(dx, dy), r, Paint()..color = color);
    }

    blob(Offset(size.width * 0.18, size.height * 0.1), size.width * 0.42,
        scheme.primaryContainer, 0);
    blob(Offset(size.width * 0.95, size.height * 0.62), size.width * 0.34,
        scheme.secondaryContainer, 0.35);
    blob(Offset(size.width * 0.05, size.height * 0.55), size.width * 0.2,
        scheme.tertiaryContainer, 0.7);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.scheme != scheme;
}

// ─── Сцена 1: двое сходятся ───────────────────────────────────────────────────

class _DuoScene extends StatefulWidget {
  const _DuoScene({required this.scheme, required this.still});

  final ColorScheme scheme;
  final bool still;

  @override
  State<_DuoScene> createState() => _DuoSceneState();
}

class _DuoSceneState extends State<_DuoScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _ctrl.value = 0.6;
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          // Кружки СТОЯТ рядом и лишь дышат: раньше они разъезжались на
          // полэкрана и половину времени сцена выглядела пустой.
          final breathe = math.sin(t * math.pi * 2);
          final gap = 31 + breathe * 5;
          final ringT = ((t * 2) % 1.0);

          return SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(260, 260),
                  painter: _RingPainter(color: cs.primary, t: ringT),
                ),
                Transform.translate(
                  offset: Offset(-gap, 0),
                  child: _Avatar(
                    letter: 'Т',
                    bg: cs.primary,
                    ink: cs.onPrimary,
                    scale: 1 + 0.03 * breathe,
                  ),
                ),
                Transform.translate(
                  offset: Offset(gap, 0),
                  child: _Avatar(
                    letter: 'А',
                    bg: cs.secondaryContainer,
                    ink: cs.onSecondaryContainer,
                    scale: 1 - 0.03 * breathe,
                  ),
                ),

              ],
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.letter,
    required this.bg,
    required this.ink,
    required this.scale,
  });

  final String letter;
  final Color bg;
  final Color ink;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: AppFonts.unbounded(size: 27, weight: 700, color: ink),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.18).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      canvas.drawCircle(
        center,
        48 + 62 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

// ─── Сцена 2: фигура течёт ────────────────────────────────────────────────────

class _MorphScene extends StatefulWidget {
  const _MorphScene({
    required this.scheme,
    required this.theme,
    required this.still,
  });

  final ColorScheme scheme;
  final AppTheme theme;
  final bool still;

  @override
  State<_MorphScene> createState() => _MorphSceneState();
}

class _MorphSceneState extends State<_MorphScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _ctrl.value = 0.25;
    } else {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.theme.fillColor;
    final ink = AppThemes.onColor(fill, mode: widget.theme.brightness);

    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_ctrl.value);
          // Это КАРТОЧКА с наклоном, и она ею остаётся: скругление гуляет в
          // узких пределах, до круга не доходя. Прежний размах от 48 до 104
          // превращал фигуру в розовое пятно, и половину времени сцена не
          // читалась вовсе.
          return Transform.rotate(
            angle: -0.10 + 0.05 * t,
            child: Container(
              width: 212,
              height: 212,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(34 + 16 * t),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.favorite_border_rounded, size: 92, color: ink),
            ),
          );
        },
      ),
    );
  }
}

// ─── Сцена 3: круг наливается ─────────────────────────────────────────────────

class _DialScene extends StatefulWidget {
  const _DialScene({
    required this.scheme,
    required this.theme,
    required this.still,
  });

  final ColorScheme scheme;
  final AppTheme theme;
  final bool still;

  @override
  State<_DialScene> createState() => _DialSceneState();
}

class _DialSceneState extends State<_DialScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _ctrl.value = 1;
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.scheme;
    final fill = widget.theme.fillColor;
    final ink = AppThemes.onColor(fill, mode: widget.theme.brightness);

    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // Шесть секторов наливаются по одному, потом круг гаснет и начинает
          // заново: тот же круг, что встретит человека на главной.
          final filled = (_ctrl.value * 6).floor().clamp(0, 6);
          final part = (_ctrl.value * 6) - filled;
          return SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(250, 250),
                  painter: _DialPainter(
                    track: widget.theme.timerDialBackground,
                    fill: fill,
                    hole: widget.theme.bgGradient.first,
                    filled: filled,
                    part: part,
                  ),
                ),
                Text(
                  '$filled',
                  style:
                      AppFonts.unbounded(size: 40, weight: 800, color: ink),
                ),
                Positioned(
                  bottom: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Pill(
                          icon: Icons.mood_rounded,
                          label: LocaleService.current.mood,
                          bg: cs.surfaceContainerLowest,
                          ink: cs.onSurface),
                      const SizedBox(width: 7),
                      _Pill(
                          icon: Icons.widgets_rounded,
                          label: LocaleService.current.widgets,
                          bg: fill,
                          ink: ink),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.bg,
    required this.ink,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: ink),
          const SizedBox(width: 6),
          Text(label,
              style: AppFonts.onest(size: 12, weight: 600, color: ink)),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.track,
    required this.fill,
    required this.hole,
    required this.filled,
    required this.part,
  });

  final Color track;
  final Color fill;
  final Color hole;
  final int filled;
  final double part;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;

    // Сплошной круг, а не пирог со спицами. Разрезанный белыми линиями круг
    // на онбординге читался дёшево: человек ещё не знает, что это таймер, и
    // видит просто фигуру, порубленную на куски.
    canvas.drawCircle(center, r, Paint()..color = fill);

    // Заполнение показывает тонкое кольцо по краю — оно и живёт, и не спорит
    // с числом в середине.
    final ringRect = Rect.fromCircle(center: center, radius: r - 7);
    canvas.drawCircle(
      center,
      r - 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = track.withValues(alpha: 0.55),
    );
    final done = (filled + part) / 6;
    if (done > 0) {
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * done,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6
          ..color = track,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.filled != filled || old.part != part || old.fill != fill;
}
