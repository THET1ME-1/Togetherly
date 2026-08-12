import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/deep_link_service.dart';

/// Кнопки на виджетах шлют действие ссылкой: отметить настроение, сказать
/// «скучаю», открыть листик. На Android её ловит home_widget, а на iPhone схему
/// `loveapp://` первым разбирает app_links — и до обработчика виджетов ссылка
/// не доезжала. Человек жал «хорошо» в виджете, приложение открывалось, и
/// ничего не менялось.
void main() {
  group('DeepLinkService.isWidgetAction', () {
    test('отметка настроения с виджета', () {
      expect(
        DeepLinkService.isWidgetAction(Uri.parse('loveapp://mood?id=happy')),
        isTrue,
      );
    });

    test('«скучаю» и листик тоже с виджета', () {
      expect(DeepLinkService.isWidgetAction(Uri.parse('loveapp://miss')), isTrue);
      expect(DeepLinkService.isWidgetAction(Uri.parse('loveapp://note')), isTrue);
    });

    test('приглашение виджетом не считается', () {
      expect(
        DeepLinkService.isWidgetAction(Uri.parse('loveapp://invite/AVQVV3')),
        isFalse,
      );
    });

    test('обычная веб-ссылка виджетом не считается', () {
      expect(
        DeepLinkService.isWidgetAction(
          Uri.parse('https://togetherly.duckdns.org/invite/AVQVV3'),
        ),
        isFalse,
      );
    });
  });
}
