import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';

/// Выбор сетки для пиксель-арта — отдельным экраном, как в макете: имя раздела
/// во весь верх, поля ширины и высоты, готовые размеры, живое превью формы
/// листа и кнопка-пилюля внизу.
///
/// Возвращает `(ширина, высота)` либо null, если пользователь ушёл назад.
/// Размер задаётся один раз: точки штрихов хранятся в долях листа, и смена
/// сетки сдвинула бы рисунок у обоих в паре.
class PixelSizeScreen extends StatefulWidget {
  const PixelSizeScreen({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<PixelSizeScreen> createState() => _PixelSizeScreenState();
}

class _PixelSizeScreenState extends State<PixelSizeScreen> {
  static const int _min = 2;
  static const int _max = 400;
  static const List<(int, int)> _presets = [
    (5, 5),
    (12, 15),
    (32, 40),
    (64, 80),
    (200, 100),
  ];

  final _wCtrl = TextEditingController(text: '32');
  final _hCtrl = TextEditingController(text: '40');

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  int get _w => (int.tryParse(_wCtrl.text.trim()) ?? 32).clamp(_min, _max);
  int get _h => (int.tryParse(_hCtrl.text.trim()) ?? 40).clamp(_min, _max);

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;
    final g = _gcd(_w, _h);

    return Scaffold(
      backgroundColor: t.bgGradient.first,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: t.cardSurface,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.arrow_back_rounded,
                        size: 20, color: t.textPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.pixelScreenTitle,
                style: AppFonts.unbounded(
                  size: 62,
                  weight: 800,
                  height: 0.86,
                  letterSpacing: -3,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.pixelCanvasHint,
                style: TextStyle(fontSize: 13.5, color: t.textSecondary),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _field(t, _wCtrl, s.pixelWidth)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '×',
                      style: AppFonts.unbounded(
                        size: 20,
                        weight: 700,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                  Expanded(child: _field(t, _hCtrl, s.pixelHeight)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets) _preset(t, p.$1, p.$2),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(child: _preview(t, g)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, (_w, _h)),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: t.primary.computeLuminance() > 0.55
                        ? const Color(0xFF16161A)
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    s.pixelCanvasCreateAction,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(AppTheme t, TextEditingController c, String label) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: t.primary,
            ),
          ),
          TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: AppFonts.unbounded(
              size: 26,
              weight: 700,
              letterSpacing: -0.5,
              color: t.textPrimary,
            ),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preset(AppTheme t, int pw, int ph) {
    final active = _w == pw && _h == ph;
    return GestureDetector(
      onTap: () => setState(() {
        _wCtrl.text = '$pw';
        _hCtrl.text = '$ph';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? t.primaryLight : t.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$pw×$ph',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: active ? t.primary : t.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Превью формы листа: лист принимает пропорцию сетки, поэтому 200×100
  /// ложится горизонтально, а 5×5 — квадратом.
  Widget _preview(AppTheme t, int g) {
    final s = LocaleService.current;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(26),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _w / _h,
                child: CustomPaint(
                  painter: _PreviewPainter(
                    cols: _w,
                    rows: _h,
                    sheet: Colors.white,
                    line: t.primary.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${s.pixelCanvasSummary(_w * _h, (1600 / _w).round())} · ${_w ~/ g} : ${_h ~/ g}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.cols,
    required this.rows,
    required this.sheet,
    required this.line,
  });

  final int cols;
  final int rows;
  final Color sheet;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(rrect, Paint()..color = sheet);
    canvas.save();
    canvas.clipRRect(rrect);

    // Мельче трёх точек на клетку сетка превращается в шум — не рисуем.
    final cw = size.width / cols;
    final ch = size.height / rows;
    if (cw >= 3 && ch >= 3) {
      final p = Paint()
        ..color = line
        ..strokeWidth = 1;
      for (int i = 1; i < cols; i++) {
        final x = i * cw;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
      for (int j = 1; j < rows; j++) {
        final y = j * ch;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.cols != cols || old.rows != rows || old.sheet != sheet;
}
