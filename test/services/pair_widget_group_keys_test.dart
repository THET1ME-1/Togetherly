// У каждой пары свои ключи в контейнере виджета.
//
// Парный виджет с самого начала жил на общих ключах — `my_status`,
// `partner_photo_path` и прочих без пары в имени. Один набор на все связи: чья
// синхронизация прошла последней, ту виджет и рисует, независимо от того, к
// какой паре он привязан. У человека с двумя связями это видно сразу — на столе
// половина одной пары рядом с половиной другой (снимок 04.09.2026), а фоновое
// обновление добивало картину: оно обновляет только пару из
// `love_widget_group_id`, поэтому вторая застывала до переключения в приложении.
//
// Остальные виджеты («Настроение», «Дни вместе», «Скучаю», заметка, кольца
// года) давно живут по паре: `<тип>_<пара>_<поле>` плюс указатель
// `<тип>_latest_group`. Парный переезжает на тот же порядок.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/pair_widget_payload.dart';

void main() {
  test('ключ пары несёт её номер', () {
    expect(pairWidgetKey('abc123', 'my_status'), 'love_abc123_my_status');
    expect(pairWidgetKey('abc123', 'partner_photo_path'),
        'love_abc123_partner_photo_path');
  });

  test('без пары ключ остаётся общим', () {
    expect(pairWidgetKey('', 'my_status'), 'my_status');
  });

  test('набор раскладывается по паре целиком', () {
    final byPair = pairWidgetKeysFor('g7', const {
      'my_status': 'дома',
      'partner_mood': 'Смех',
    });
    expect(byPair['love_g7_my_status'], 'дома');
    expect(byPair['love_g7_partner_mood'], 'Смех');
    expect(byPair.containsKey('my_status'), isFalse,
        reason: 'общие ключи пишутся отдельно, тут только пара');
  });

  test('без пары набор не переименовывается', () {
    final byPair = pairWidgetKeysFor('', const {'my_status': 'дома'});
    expect(byPair, {'my_status': 'дома'});
  });

  test('признак готовности отмечает пару, у которой ключи уже разложены', () {
    // Пока приложение не обновило контейнер, нативный виджет обязан читать
    // старые общие ключи: иначе после установки сборки виджет опустеет.
    expect(pairWidgetReadyKey('g7'), 'love_g7_ready');
  });
}
