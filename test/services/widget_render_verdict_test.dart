// Название события должно само говорить, что случилось: искать по времени —
// лишний круг, а в Bugsink список issue виден заголовками.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/widget_render_log.dart';

void main() {
  test('маленький оборвался на середине', () {
    final rows = parseWidgetRenderLog(
      '1|small|photo-partner|start=1;path=1;bytes=900000;mem=9',
    );
    expect(widgetRenderVerdict(rows), 'small оборвался (память 9 МБ)');
  });

  test('картинка не разжалась', () {
    final rows =
        parseWidgetRenderLog('1|small|photo-mine|decoded=0;reason=no-thumb');
    expect(widgetRenderVerdict(rows), 'small не разжал картинку (no-thumb)');
  });

  test('файла нет на диске', () {
    final rows = parseWidgetRenderLog('1|medium|photo-mine|path=1;missing=1');
    expect(widgetRenderVerdict(rows), 'medium: файла нет на диске');
  });

  test('всё хорошо', () {
    final rows = parseWidgetRenderLog(
      '1|small|photo-mine|start=1;path=1;bytes=100\n'
      '2|small|photo-mine|decoded=1;px=600x800;mem=20',
    );
    expect(widgetRenderVerdict(rows), 'ок');
  });

  test('пусто — журнала нет', () {
    expect(widgetRenderVerdict(const []), 'журнал пуст');
  });
}
