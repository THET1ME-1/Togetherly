import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/home_widget_service.dart';

/// Шаг «поставить виджет» на iPhone закрывает отметка расширения
/// (обращение 268): кнопки «добавить» там нет, и до 16.10.2026 шаг не
/// закрывался ни у кого. Разъедутся имена ключа в Swift и Dart — шаг снова
/// молча повиснет, ошибки при этом не будет нигде.
void main() {
  final store = File('ios/TogetherlyWidget/SharedStore.swift').readAsStringSync();
  final bundle =
      File('ios/TogetherlyWidget/TogetherlyWidgetBundle.swift').readAsStringSync();
  final home = File('lib/screens/home_screen.dart').readAsStringSync();

  test('ключ отметки одинаков в расширении и в приложении', () {
    final presence = RegExp(
      r'enum WidgetPresence \{.*?static let key = "([^"]+)"',
      dotAll: true,
    ).firstMatch(store);
    expect(presence, isNotNull, reason: 'enum WidgetPresence пропал');
    expect(presence!.group(1), kWidgetOnScreenKey);
  });

  test('отметку ставит таймлайн поставленного виджета, а не галерея', () {
    final timeline = bundle.substring(bundle.indexOf('func getTimeline('));
    final body = timeline.substring(0, timeline.indexOf('completion(Timeline'));
    expect(body, contains('WidgetPresence.mark()'));
    expect(body, contains('!context.isPreview'));
    final snapshot = bundle.substring(
      bundle.indexOf('func getSnapshot('),
      bundle.indexOf('func getTimeline('),
    );
    expect(snapshot, isNot(contains('WidgetPresence.mark()')));
  });

  test('главная спрашивает систему на входе и при возврате', () {
    expect(home, contains('anyWidgetOnScreen()'));
    final calls = '_checkWidgetOnScreen()'.allMatchesIn(home);
    // Объявление плюс вызов в _loadPromptState и в onResume.
    expect(calls, greaterThanOrEqualTo(3));
  });

  test('ссылка-приглашение открывает «Связь» и при живой паре', () {
    // Обращение 272: с парой ссылка подруги вела на главную с таймером своей
    // пары, а код молча лежал в буфере.
    final start = home.indexOf('inviteCodeStream.listen(');
    expect(start, greaterThan(0));
    final handler = home.substring(start, home.indexOf('});', start));
    expect(handler, isNot(contains('isPaired')));
    expect(home, contains('hasPendingInviteCode'));
  });
}

extension on String {
  int allMatchesIn(String text) => RegExp(RegExp.escape(this)).allMatches(text).length;
}
