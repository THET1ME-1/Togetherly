import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/locale_service.dart';
import '../models/postcard_template.dart';

/// Четыре «бумажные» открытки: билет, чек, телеграмма, посылка.
///
/// Общее у них одно: это узнаваемый документ из настоящего мира, подделанный
/// под пару. Работает форма бумажки и типографика, а не сердечки по углам —
/// поэтому здесь нет ни одного декоративного значка, кроме почтового штемпеля
/// и пометки «хрупкое».
///
/// Размер задаёт родитель (квадрат), внутри всё считается от ширины: открытку
/// снимают в картинку при pixelRatio 2.5, и любые фиксированные пиксели
/// разъехались бы между экранами.

/// Обёртка редактирования — та же роль, что у приватного `_editable` в
/// [PostcardCard], но публичная: новые открытки живут отдельным файлом.
class PostcardEditable extends StatelessWidget {
  const PostcardEditable({
    super.key,
    required this.block,
    required this.isEditing,
    required this.onTap,
    required this.child,
    this.highlight = Colors.black,
  });

  final PostcardTextBlock block;
  final bool isEditing;
  final void Function(String)? onTap;
  final Widget child;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) return child;
    return GestureDetector(
      onTap: () => onTap?.call(block.id),
      child: Container(
        decoration: BoxDecoration(
          color: highlight.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: highlight.withValues(alpha: 0.28)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

PostcardTextBlock _block(List<PostcardTextBlock> blocks, String id) =>
    blocks.firstWhere((b) => b.id == id,
        orElse: () => PostcardTextBlock(id: id, label: id, text: ''));

// ─────────────────────────────────────────────────────────────────────────────
// 1. Билет
// ─────────────────────────────────────────────────────────────────────────────

class TicketPostcard extends StatelessWidget {
  const TicketPostcard({
    super.key,
    required this.days,
    required this.blocks,
    required this.isEditing,
    required this.onBlockTap,
  });

  final int days;
  final List<PostcardTextBlock> blocks;
  final bool isEditing;
  final void Function(String)? onBlockTap;

  static const Color _paper = Color(0xFFE9DCC2);
  static const Color _ink = Color(0xFF241C12);
  static const Color _faded = Color(0xFF8A7550);
  static const Color _stamp = Color(0xFFC0567F);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final s = LocaleService.current;
          return Container(
            color: _paper,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(w * .08, w * .09, w * .08, w * .04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.pcTicketRoute.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: w * .033,
                            fontWeight: FontWeight.w600,
                            letterSpacing: w * .006,
                            color: _faded,
                          ),
                        ),
                        SizedBox(height: w * .025),
                        PostcardEditable(
                          block: _block(blocks, 'names'),
                          isEditing: isEditing,
                          onTap: onBlockTap,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _block(blocks, 'names').text,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: w * .13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -w * .005,
                                height: 1.05,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: w * .028),
                        PostcardEditable(
                          block: _block(blocks, 'message'),
                          isEditing: isEditing,
                          onTap: onBlockTap,
                          child: Text(
                            _block(blocks, 'message').text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: w * .05,
                              height: 1.35,
                              color: const Color(0xFF4A3B28),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Линия отрыва с высечками по краям — по ней билет и узнаётся.
                SizedBox(
                  height: w * .07,
                  child: CustomPaint(
                    size: Size(w, w * .07),
                    painter: _PerforationPainter(),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(w * .08, 0, w * .08, w * .08),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$days',
                              style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: w * .2,
                                fontWeight: FontWeight.w800,
                                height: .9,
                                letterSpacing: -w * .008,
                                color: _ink,
                              ),
                            ),
                            SizedBox(height: w * .022),
                            Text(
                              _block(blocks, 'days_label').text.toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: w * .032,
                                fontWeight: FontWeight.w600,
                                letterSpacing: w * .006,
                                color: _faded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Stamp(size: w * .22, date: DateTime.now()),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Пунктир отрыва и две круглые высечки по краям.
class _PerforationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dash = Paint()
      ..color = const Color(0xFFC3AE85)
      ..strokeWidth = size.height * .09
      ..strokeCap = StrokeCap.round;
    final notch = Paint()..color = const Color(0xFFD3C3A2);
    final r = size.height * .55;

    // Высечки нарисованы тоном темнее бумаги, а не фоном страницы: открытка
    // уезжает картинкой в чат, и «дырка» под чужим фоном выглядела бы заплатой.
    canvas.drawCircle(Offset(0, y), r, notch);
    canvas.drawCircle(Offset(size.width, y), r, notch);

    var x = r + size.height * .5;
    final step = size.width * .028;
    while (x < size.width - r - size.height * .5) {
      canvas.drawLine(Offset(x, y), Offset(x + step * .5, y), dash);
      x += step;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.size, required this.date});

  final double size;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return Transform.rotate(
      angle: -11 * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TicketPostcard._stamp, width: size * .035),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$d·$m',
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: size * .17,
                  fontWeight: FontWeight.w700,
                  color: TicketPostcard._stamp,
                )),
            Text('${date.year}',
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: size * .17,
                  fontWeight: FontWeight.w700,
                  color: TicketPostcard._stamp,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Чек
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptPostcard extends StatelessWidget {
  const ReceiptPostcard({
    super.key,
    required this.days,
    required this.blocks,
    required this.isEditing,
    required this.onBlockTap,
  });

  final int days;
  final List<PostcardTextBlock> blocks;
  final bool isEditing;
  final void Function(String)? onBlockTap;

  static const Color _paper = Color(0xFFFBFAF6);
  static const Color _ink = Color(0xFF20201C);
  static const Color _faded = Color(0xFF7C7A70);

  /// Моноширинный шрифт системы: лента чека набирается только им, а тащить
  /// ради одной открытки ещё один файл шрифта в сборку не стоит.
  static const String _mono = 'monospace';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final s = LocaleService.current;
          final now = DateTime.now();
          final date = '${now.day.toString().padLeft(2, '0')}.'
              '${now.month.toString().padLeft(2, '0')}.${now.year}';

          return Container(
            color: _paper,
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(w * .09, w * .07, w * .09, w * .085),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PostcardEditable(
                        block: _block(blocks, 'names'),
                        isEditing: isEditing,
                        onTap: onBlockTap,
                        child: Text(
                          _block(blocks, 'names').text.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: _mono,
                            fontSize: w * .055,
                            fontWeight: FontWeight.w700,
                            letterSpacing: w * .012,
                            color: _ink,
                          ),
                        ),
                      ),
                      SizedBox(height: w * .018),
                      Text(
                        '$date · ${s.pcReceiptShift(days)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _mono,
                          fontSize: w * .033,
                          letterSpacing: w * .004,
                          color: _faded,
                        ),
                      ),
                      SizedBox(height: w * .025),
                      _rule(w),
                      for (final line in _block(blocks, 'items').text.split('\n'))
                        if (line.trim().isNotEmpty) _row(w, line),
                      _rule(w),
                      SizedBox(height: w * .01),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              s.pcReceiptTotal.toUpperCase(),
                              style: TextStyle(
                                fontFamily: _mono,
                                fontSize: w * .045,
                                fontWeight: FontWeight.w700,
                                color: _ink,
                              ),
                            ),
                          ),
                          Text(
                            '$days',
                            style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: w * .115,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -w * .005,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _block(blocks, 'days_label').text,
                        style: TextStyle(
                          fontFamily: _mono,
                          fontSize: w * .036,
                          color: _faded,
                        ),
                      ),
                      const Spacer(),
                      PostcardEditable(
                        block: _block(blocks, 'message'),
                        isEditing: isEditing,
                        onTap: onBlockTap,
                        child: Text(
                          _block(blocks, 'message').text.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: _mono,
                            fontSize: w * .031,
                            letterSpacing: w * .008,
                            color: _faded,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Оторванный низ ленты.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: w * .045,
                  child: CustomPaint(painter: _TornEdgePainter(_paper)),
                ),
              ],
            ),
          );
        },
      );

  Widget _rule(double w) => Padding(
        padding: EdgeInsets.symmetric(vertical: w * .014),
        child: CustomPaint(
          size: Size(double.infinity, 1),
          painter: _DashedRulePainter(),
        ),
      );

  Widget _row(double w, String line) {
    // «Название — 128»: считаем последнюю группу цифр значением, остальное
    // названием. Так строку можно править в одном поле, без формы из полей.
    final match = RegExp(r'^(.*?)[\s—-]*(\d+|[^\d\s]{1,12})$').firstMatch(line.trim());
    final left = (match?.group(1) ?? line).trim();
    final right = (match?.group(2) ?? '').trim();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * .004),
      child: Row(
        children: [
          Expanded(
            child: Text(
              left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: _mono, fontSize: w * .034, color: _ink),
            ),
          ),
          Text(
            right,
            style: TextStyle(
                fontFamily: _mono, fontSize: w * .034, color: _ink),
          ),
        ],
      ),
    );
  }
}

class _DashedRulePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFC8C5B8)
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TornEdgePainter extends CustomPainter {
  const _TornEdgePainter(this.paper);

  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, 0);
    final step = size.width / 16;
    for (var i = 0; i < 16; i++) {
      final x = step * i;
      path.lineTo(x + step / 2, size.height);
      path.lineTo(x + step, 0);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    // Зубцы вырезаны цветом бумаги поверх фона карточки: рисуем «пустоту»,
    // а не белую полоску, поэтому на любом фоне край выглядит оторванным.
    canvas.drawPath(path, Paint()..blendMode = BlendMode.clear);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Телеграмма
// ─────────────────────────────────────────────────────────────────────────────

class TelegramPostcard extends StatelessWidget {
  const TelegramPostcard({
    super.key,
    required this.days,
    required this.blocks,
    required this.isEditing,
    required this.onBlockTap,
  });

  final int days;
  final List<PostcardTextBlock> blocks;
  final bool isEditing;
  final void Function(String)? onBlockTap;

  static const Color _paper = Color(0xFFF3EEE2);
  static const Color _ink = Color(0xFF1E1A14);
  static const Color _faded = Color(0xFF7A6F5C);
  static const Color _rule = Color(0xFFD6CBB4);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final s = LocaleService.current;
          final now = DateTime.now();
          final months = s.cycleMonthsGenitive;

          return Container(
            color: _paper,
            child: CustomPaint(
              painter: _AirmailBorderPainter(w * .035),
              child: Padding(
                padding: EdgeInsets.all(w * .095),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.pcTelegramTitle.toUpperCase(),
                            style: _meta(w)),
                        Text('№ $days', style: _meta(w)),
                      ],
                    ),
                    SizedBox(height: w * .028),
                    Container(height: 1, color: _rule),
                    Expanded(
                      child: Center(
                        child: PostcardEditable(
                          block: _block(blocks, 'message'),
                          isEditing: isEditing,
                          onTap: onBlockTap,
                          child: Text(
                            _block(blocks, 'message').text.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontSize: w * .075,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              letterSpacing: w * .002,
                              color: _ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(height: 1, color: _rule),
                    SizedBox(height: w * .035),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: PostcardEditable(
                            block: _block(blocks, 'names'),
                            isEditing: isEditing,
                            onTap: onBlockTap,
                            child: Text(
                              _block(blocks, 'names').text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: w * .062,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -w * .002,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '${now.day} ${months[now.month - 1]} ${now.year}',
                          style: _meta(w),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  TextStyle _meta(double w) => TextStyle(
        fontFamily: 'Onest',
        fontSize: w * .032,
        fontWeight: FontWeight.w600,
        letterSpacing: w * .006,
        color: _faded,
      );
}

/// Сине-красная кайма авиапочты по периметру.
class _AirmailBorderPainter extends CustomPainter {
  const _AirmailBorderPainter(this.band);

  final double band;
  static const Color _blue = Color(0xFF2C5AA0);
  static const Color _red = Color(0xFFC0392B);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final paintBlue = Paint()
      ..color = _blue
      ..strokeWidth = band * .9
      ..strokeCap = StrokeCap.butt;
    final paintRed = Paint()
      ..color = _red
      ..strokeWidth = band * .9
      ..strokeCap = StrokeCap.butt;

    // Полосы идут по диагонали и обрезаются рамкой: так кайма выглядит
    // непрерывной на углах, без стыков и наложений.
    final step = band * 1.6;
    var i = 0;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      final p = i.isEven ? paintBlue : paintRed;
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
      i++;
    }

    // Середину закрываем бумагой, оставляя только кайму по краю.
    final inner = Rect.fromLTWH(band, band, size.width - band * 2, size.height - band * 2);
    canvas.drawRect(inner, Paint()..color = TelegramPostcard._paper);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Посылка
// ─────────────────────────────────────────────────────────────────────────────

class ParcelPostcard extends StatelessWidget {
  const ParcelPostcard({
    super.key,
    required this.days,
    required this.blocks,
    required this.isEditing,
    required this.onBlockTap,
  });

  final int days;
  final List<PostcardTextBlock> blocks;
  final bool isEditing;
  final void Function(String)? onBlockTap;

  static const Color _box = Color(0xFFD8C4A0);
  static const Color _label = Color(0xFFFCFBF7);
  static const Color _ink = Color(0xFF2A2016);
  static const Color _faded = Color(0xFF8B7A5E);
  static const Color _care = Color(0xFFB03A2E);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final s = LocaleService.current;
          final now = DateTime.now();
          final track = 'RU $days '
              '${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')} '
              '${now.year % 100} RU';

          return Container(
            color: _box,
            padding: EdgeInsets.all(w * .07),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_border_rounded,
                        size: w * .055, color: _care),
                    SizedBox(width: w * .022),
                    Expanded(
                      child: Text(
                        s.pcParcelCare.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: w * .034,
                          fontWeight: FontWeight.w700,
                          letterSpacing: w * .005,
                          color: _care,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: w * .045),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _label,
                      borderRadius: BorderRadius.circular(w * .02),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3C280A).withValues(alpha: .16),
                          blurRadius: w * .03,
                          offset: Offset(0, w * .008),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.all(w * .05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.pcParcelTo.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: w * .032,
                            fontWeight: FontWeight.w600,
                            letterSpacing: w * .006,
                            color: _faded,
                          ),
                        ),
                        SizedBox(height: w * .012),
                        PostcardEditable(
                          block: _block(blocks, 'names'),
                          isEditing: isEditing,
                          onTap: onBlockTap,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _block(blocks, 'names').text,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Unbounded',
                                fontSize: w * .095,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -w * .004,
                                height: 1.1,
                                color: _ink,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: w * .035),
                        Container(height: 1, color: const Color(0xFFE4DCC9)),
                        SizedBox(height: w * .03),
                        PostcardEditable(
                          block: _block(blocks, 'message'),
                          isEditing: isEditing,
                          onTap: onBlockTap,
                          child: Text(
                            _block(blocks, 'message').text,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: w * .042,
                              height: 1.45,
                              color: const Color(0xFF5C4E3A),
                            ),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: w * .13,
                          child: CustomPaint(
                            size: Size(double.infinity, w * .13),
                            painter: _BarcodePainter(days),
                          ),
                        ),
                        SizedBox(height: w * .022),
                        Text(
                          track,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: w * .033,
                            letterSpacing: w * .012,
                            color: const Color(0xFF5C4E3A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Штрихкод, у которого ширины полос считаются от числа дней: у каждой пары
/// он свой и не меняется день ото дня случайным образом.
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed == 0 ? 1 : seed);
    final paint = Paint()..color = const Color(0xFF2A2016);
    var x = 0.0;
    while (x < size.width) {
      final barWidth = rnd.nextBool() ? size.width * .004 : size.width * .009;
      final tall = rnd.nextInt(4) != 0;
      final h = tall ? size.height : size.height * .72;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, barWidth, h), paint);
      x += barWidth + size.width * .006;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) =>
      oldDelegate.seed != seed;
}
