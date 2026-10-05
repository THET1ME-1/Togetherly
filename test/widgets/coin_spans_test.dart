import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/common/coin_image.dart';

/// Эмодзи 🪙 в словаре — метка места, а не сама монета: на экране вместо него
/// встаёт живая монета TY (`CoinImage`). Системный эмодзи у каждого телефона
/// свой и выбивается из оформления (жалоба 05.10.2026 на лист перед
/// совместным просмотром).
void main() {
  test('метка монеты становится картинкой, текст вокруг остаётся', () {
    final spans = coinSpans('получишь монеты 🪙', const TextStyle(fontSize: 16));
    final texts = spans.whereType<TextSpan>().map((s) => s.text).join();
    expect(texts.contains('🪙'), isFalse, reason: 'эмодзи не должен остаться в тексте');
    expect(texts, 'получишь монеты ');
    final coins = spans.whereType<WidgetSpan>().toList();
    expect(coins, hasLength(1));
    expect(coins.single.child, isA<CoinImage>());
  });

  test('монета в середине и несколько монет', () {
    final spans = coinSpans('за 30 🪙 или 60 🪙 в месяц', null);
    expect(spans.whereType<WidgetSpan>(), hasLength(2));
    expect(spans.whereType<TextSpan>().map((s) => s.text).join(), 'за 30  или 60  в месяц');
  });

  test('без метки — один кусок текста', () {
    final spans = coinSpans('просто текст', null);
    expect(spans, hasLength(1));
    expect((spans.single as TextSpan).text, 'просто текст');
  });

  test('монета ростом со строку', () {
    final coin = coinSpans('🪙', const TextStyle(fontSize: 20)).whereType<WidgetSpan>().single.child as CoinImage;
    expect(coin.side, closeTo(20 * 1.3, 0.01));
  });

  test('лист перед совместным просмотром рисует монету картинкой', () {
    final src = File('lib/screens/together/together_launcher.dart').readAsStringSync();
    expect(src.contains('coinSpans(s.watchTogetherAdPrompt'), isTrue,
        reason: 'текст листа обязан идти через coinSpans, иначе на экране эмодзи');
  });
}
