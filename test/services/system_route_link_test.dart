import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/system_route_link.dart';

/// Ссылка с виджета на iPhone, когда приложение закрыто.
///
/// Тап по виджету открывает приложение, и система отдаёт ссылку сцене
/// (`scene:willConnectTo:`). Плагин `app_links` смотрит не туда — он читает
/// `launchOptions` делегата приложения, а при сценах URL туда не кладут. Flutter
/// в этом случае толкает ссылку в системный канал маршрутов, и подобрать её
/// можно только оттуда. Пока этого не делали, тап по заметке с закрытого
/// приложения не давал ничего: «не открывается виджет на рабочем столе».
void main() {
  test('маршрут-ссылка разбирается в Uri', () {
    expect(uriFromRoute('loveapp://note'), Uri.parse('loveapp://note'));
  });

  test('информация о маршруте приходит картой', () {
    expect(uriFromRoute({'location': 'loveapp://mood?id=happy'}),
        Uri.parse('loveapp://mood?id=happy'));
  });

  test('обычные маршруты приложения не трогаем', () {
    expect(uriFromRoute('/'), isNull);
    expect(uriFromRoute('/home'), isNull);
    expect(uriFromRoute({'location': '/settings'}), isNull);
  });

  test('чужая схема тоже не наша забота', () {
    expect(uriFromRoute('https://togetherly.day/invite/AB12'), isNull);
  });

  test('мусор не роняет разбор', () {
    expect(uriFromRoute(null), isNull);
    expect(uriFromRoute(42), isNull);
    expect(uriFromRoute({'location': null}), isNull);
    expect(uriFromRoute(':::'), isNull);
  });
}
