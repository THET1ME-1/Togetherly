import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/canvas/canvas_widget_keys.dart';

/// Сторожа виджета «Рисунок на столе».
///
/// Выбор холста и рисование поверх стола живут в трёх местах разом: Kotlin,
/// манифест и Dart. Разъехались — виджет либо не ставится, либо стоит пустой,
/// и увидеть это можно только на устройстве.
void main() {
  final provider = File(
    'android/app/src/main/kotlin/com/togetherly/love/CanvasWidgetProvider.kt',
  );
  final pick = File(
    'android/app/src/main/kotlin/com/togetherly/love/CanvasPickActivity.kt',
  );
  final overlay = File(
    'android/app/src/main/kotlin/com/togetherly/love/CanvasDrawOverlayActivity.kt',
  );
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('все три размера объявлены классом и приёмником', () {
    final code = provider.readAsStringSync();
    final xml = manifest.readAsStringSync();
    for (final name in kCanvasWidgetProviders) {
      expect(code.contains('class $name'), isTrue, reason: 'нет класса $name');
      expect(xml.contains('.$name'), isTrue, reason: 'нет приёмника $name');
    }
  });

  test('холст выбирается при добавлении и через «Настроить»', () {
    for (final size in ['2x2', '2x3', '4x4']) {
      final info = File('android/app/src/main/res/xml/tg_canvas_${size}_info.xml')
          .readAsStringSync();
      expect(
        info.contains('android:configure="com.togetherly.love.CanvasPickActivity"'),
        isTrue,
        reason: 'у $size нет экрана выбора холста',
      );
      // Без этого «Настроить» у поставленного виджета не появится (Android 12+).
      expect(
        info.contains('android:widgetFeatures="reconfigurable"'),
        isTrue,
        reason: 'виджет $size нельзя перенастроить',
      );
    }
    expect(
      manifest.readAsStringSync().contains('android.appwidget.action.APPWIDGET_CONFIGURE'),
      isTrue,
      reason: 'экран выбора не объявлен как configure-activity',
    );
  });

  test('выбор холста живёт у экземпляра, а не у пары', () {
    expect(pick.readAsStringSync().contains('widget_canvas_'), isTrue);
    expect(provider.readAsStringSync().contains('CanvasPickActivity.canvasKey'), isTrue);
  });

  test('рисование поверх стола: окно, отправка и мгновенная картинка', () {
    final code = overlay.readAsStringSync();
    expect(code.contains('loveapp://canvas-stroke'), isTrue,
        reason: 'штрихи не уходят фоновому Dart');
    expect(code.contains('canvas_pending_strokes'), isTrue,
        reason: 'штрихи негде взять фоновому Dart');
    expect(code.contains('bakeIntoWidgetImage'), isTrue,
        reason: 'рисунок не появится на виджете до ответа базы');
    expect(provider.readAsStringSync().contains('CanvasDrawOverlayActivity'), isTrue,
        reason: 'тап по виджету не ведёт в рисование');
    expect(
      manifest.readAsStringSync().contains('.CanvasDrawOverlayActivity'),
      isTrue,
      reason: 'окно рисования не объявлено в манифесте',
    );
  });

  test('приложение принимает штрихи с рабочего стола', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains("host == 'canvas-stroke'"), isTrue);
    expect(main.contains('canvas_pending_strokes'), isTrue);
  });
}
