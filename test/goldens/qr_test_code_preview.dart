import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

/// Проверочный QR для сканера — чтобы не искать второй телефон.
///
/// Кодирует такой же диплинк, какой рисует экран приглашения
/// (`loveapp://invite/CODE`): сканер ищет в строке `/invite/` и забирает шесть
/// символов после. Картинку показать на ноутбуке и навести телефон.
///
/// Имя без `_test` — обычный прогон файл не подхватывает. Запуск:
/// `flutter test test/goldens/qr_test_code_preview.dart`, картинка ложится в
/// `build/qr-preview/`.
void main() {
  testWidgets('код для проверки сканера', (tester) async {
    const code = 'AB12CD';
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            width: 560,
            height: 640,
            color: Colors.white,
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: CustomPaint(
                    size: const Size(480, 480),
                    painter: _QrPainter('loveapp://invite/$code'),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  code,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/test-invite-$code.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      // Средний уровень коррекции: код будут снимать с экрана ноутбука, где
      // подмешиваются блики и муар от матрицы.
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(qr);
    final side = size.shortestSide;
    final cell = side / qr.moduleCount;
    final dx = (size.width - side) / 2;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var col = 0; col < qr.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(dx + col * cell, row * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
