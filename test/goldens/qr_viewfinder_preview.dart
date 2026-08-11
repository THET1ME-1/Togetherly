import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/qr/qr_viewfinder.dart';
import 'package:qr/qr.dart';

/// Снимок экрана сканера — вместо телефона.
///
/// Имя БЕЗ `_test`, поэтому обычный прогон его не подхватывает: файл нужен,
/// чтобы посмотреть глазами, а не сторожить регрессии. Запуск:
/// `flutter test test/goldens/qr_viewfinder_preview.dart`,
/// картинка ложится в `build/qr-preview/`.
void main() {
  testWidgets('рамка наведения поверх кадра', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: const Icon(Icons.close, color: Colors.white),
              title: const Text(
                'Сканировать QR партнёра',
                style: TextStyle(color: Colors.white, fontSize: 17),
              ),
            ),
            body: const Stack(
              fit: StackFit.expand,
              children: [_FakeCamera(), QrViewfinder(hint: 'Наведите на код партнёра')],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/qr-preview')..createSync(recursive: true);
      File('${dir.path}/viewfinder.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}

/// Подложка вместо камеры: стол, а на нём телефон партнёра с кодом. Настоящий
/// QR, а не квадратик — сразу видно, помещается ли он в окно.
class _FakeCamera extends StatelessWidget {
  const _FakeCamera();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B5B57), Color(0xFF2E2724)],
        ),
      ),
      child: Center(
        child: Container(
          width: 190,
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 150,
            height: 150,
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: CustomPaint(painter: _QrPainter('AB12CD')),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final image = QrImage(qr);
    final cell = size.width / qr.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var col = 0; col < qr.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * cell, row * cell, cell + 0.5, cell + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
