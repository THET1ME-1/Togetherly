import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/utils/readable_text.dart';
import 'package:love_app/widgets/theme/theme_leaves_layer.dart';

/// Тема «Уютная осень» (макет «Б. Листопад», 31.10.2026): терракота и мох на
/// сливочном, тёмная — печёная глина на тёплом угле, листья падают за
/// интерфейсом. Её забыли положить в обновление (владелец, 08.11.2026);
/// решение — бесплатна всем в ноябре и остаётся у тех, кто её застал.
void main() {
  final au = kPalettes.firstWhere((p) => p.name == 'Уютная осень');

  test('тема стоит своим номером и не продаётся', () {
    // Номер — ключ владения на сервере (`owned_themes`), его не двигают.
    expect(au.index, 26);
    expect(kPalettes[26], same(au));
    expect(au.isPremium, isFalse);
    expect(au.price, 0);
    expect(AppThemes.byIndex(26).isPremium, isFalse);
    expect(au.darkOnly, isFalse);
  });

  test('сезон: весь ноябрь открыта всем, потом — тем, кто её застал', () {
    final s = au.season!;
    final early = DateTime.utc(2026, 10, 1);
    final late = DateTime.utc(2026, 12, 5);
    // В ноябре — всем, даже пришедшим вчера.
    expect(s.openFor(DateTime.utc(2026, 11, 20), DateTime.utc(2026, 11, 21)), isTrue);
    // После сезона — тем, кто пришёл до 1 декабря.
    expect(s.openFor(early, DateTime.utc(2027, 3, 1)), isTrue);
    expect(s.openFor(late, DateTime.utc(2027, 3, 1)), isFalse);
    // До первого сезона темы не было.
    expect(s.openFor(early, DateTime.utc(2026, 10, 20)), isFalse);
  });

  test('обе версии нарисованы руками и несут листопад', () {
    final light = buildAppTheme(au, Brightness.light);
    final dark = buildAppTheme(au, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(light.bgGradient.first, const Color(0xFFFBF1E5));
    expect(light.scheme!.secondary, const Color(0xFF7E9461));
    expect(dark.brightness, Brightness.dark);
    expect(dark.bgGradient.first, const Color(0xFF211915));
    expect(dark.scheme!.secondary, const Color(0xFFA3B884));
    for (final t in [light, dark]) {
      expect(t.bgLeaves, isNotNull);
      expect(t.bgLeaves!.assets, hasLength(4));
    }
    // На тёмном листья приглушены, иначе слишком яркие.
    expect(dark.bgLeaves!.opacity, lessThan(light.bgLeaves!.opacity));
  });

  test('сочность не теряет листопад и фон', () {
    for (final b in Brightness.values) {
      for (final f in SchemeFlavor.values) {
        final t = buildAppTheme(au, b, flavor: f);
        expect(t.bgLeaves, isNotNull, reason: '${b.name} ${f.name}');
        final ink = AppThemes.onColor(t.fillColor, mode: t.brightness);
        expect(contrastRatio(ink, t.fillColor), greaterThanOrEqualTo(3.0),
            reason: '${b.name} ${f.name}');
      }
    }
  });

  test('картинки листьев и значка лежат в ресурсах', () {
    for (final a in [...AppThemes.autumn.bgLeaves!.assets, au.badge!.asset]) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });

  test('лист выходит из-за верхнего края и уходит за нижний', () {
    const size = Size(400, 800);
    for (final l in kFallingLeaves) {
      // Начало полёта: время, когда (секунды + задержка) кратны полёту.
      final start = leafPosition(l, size, l.seconds - l.delay);
      final end = leafPosition(l, size, l.seconds - l.delay - 0.001);
      expect(start.at.dy, lessThan(0), reason: '${l.x}');
      expect(end.at.dy, greaterThan(size.height), reason: '${l.x}');
      // Покачивание не уводит лист за края экрана.
      for (var s = 0.0; s < l.seconds; s += 0.5) {
        final p = leafPosition(l, size, s);
        expect(p.at.dx, inInclusiveRange(-l.size, size.width), reason: '${l.x} $s');
      }
    }
  });
}
