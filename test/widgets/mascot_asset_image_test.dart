import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/widgets/active_mascot_widget.dart';

/// Персонажи приходят двумя путями: часть лежит в сборке, часть — записью в
/// `catalog_items`, и тогда путь оказывается полным адресом. Такой адрес уходил
/// в `Image.asset`: на экране заглушка вместо маскота, в панели крашей
/// «Unable to load asset: https://…».
void main() {
  group('buildMascotAssetImage', () {
    testWidgets('локальный путь берёт картинку из сборки', (tester) async {
      final widget = buildMascotAssetImage('assets/images/icons/coin.webp');
      expect(widget, isA<Image>());
    });

    testWidgets('адрес из каталога грузится по сети', (tester) async {
      final widget = buildMascotAssetImage(
        'https://togetherly.duckdns.org/api/files/catalog_items/dog/kiss.webp',
      );
      expect(widget, isA<CachedNetworkImage>());
    });

    testWidgets('адрес с http тоже считается сетевым', (tester) async {
      final widget = buildMascotAssetImage('http://example.org/dog/kiss.webp');
      expect(widget, isA<CachedNetworkImage>());
    });
  });
}
