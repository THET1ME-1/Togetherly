import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/cloud_mascot.dart';
import 'package:love_app/models/gift_art.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/mascot_anim.dart';
import 'package:love_app/models/mascot_sleep.dart';
import 'package:love_app/services/catalog_service.dart';
import 'package:love_app/services/mascot_service.dart';
import 'package:love_app/services/tu_wear_service.dart';
import 'package:love_app/theme/app_palettes.dart';
import 'package:love_app/widgets/active_mascot_widget.dart';
import 'package:love_app/widgets/mascot/cloud_mascot_view.dart';
import 'package:love_app/widgets/mascot/lockstep_art.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Обращение 17.11.2026: «Мой партнёр не видит, как я одел нашего Ту». Наряд
// жил только в памяти телефона, и у партнёра Ту был в его собственном. Теперь
// на главной в режиме «партнёра» Ту в наряде партнёра из его записи виджета.
void main() {
  Map<String, dynamic> wearRow(String key, String cat) => {
        'id': 'wear_$key',
        'kind': 'wear',
        'name_ru': key,
        'name_en': key,
        'sort': 500,
        'data': {
          'key': key,
          'cat': cat,
          'src': 'chest',
          'icon': 'tuw_${key}_icon',
          'layers': {
            'idle_base': ['tuw_${key}_idle_base_b', 'tuw_${key}_idle_base_f'],
          },
        },
      };

  setUp(() {
    CatalogService.instance.debugApply([wearRow('blanket', 'neck'), wearRow('scarf', 'neck')]);
    CatalogService.instance.debugSetGiftArt(const [
      GiftArt(key: 'cloud_idle_base', lgUrl: 'art://cloud_idle_base'),
      GiftArt(key: 'tuw_blanket_idle_base_b', lgUrl: 'art://blanket_b'),
      GiftArt(key: 'tuw_blanket_idle_base_f', lgUrl: 'art://blanket_f'),
      GiftArt(key: 'tuw_scarf_idle_base_b', lgUrl: 'art://scarf_b'),
      GiftArt(key: 'tuw_scarf_idle_base_f', lgUrl: 'art://scarf_f'),
    ]);
    // Я ношу шарф, плед — вещь партнёра, у меня её нет.
    TuWearService.instance.debugSet(outfit: const {'neck': 'scarf'}, granted: const {'scarf'});
    TuWearService.instance.setPartnerOutfit(null);
  });

  List<String> layerUrls(WidgetTester tester) {
    final art = find.byType(LockstepArt);
    if (art.evaluate().isEmpty) return const [];
    return [for (final l in tester.widget<LockstepArt>(art.first).layers) l.url];
  }

  Future<void> pumpCloud(WidgetTester tester, {required bool partner}) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(child: CloudMascotView(size: 96, anim: MascotAnimState.freeze, partnerOutfit: partner)),
    ));
    await tester.pump();
  }

  testWidgets('Ту партнёра — в наряде партнёра, хотя у меня этой вещи нет', (tester) async {
    TuWearService.instance.setPartnerOutfit(const {'neck': 'blanket'});
    await pumpCloud(tester, partner: true);
    expect(layerUrls(tester), containsAll(['art://blanket_b', 'art://blanket_f']));
    expect(layerUrls(tester), isNot(contains('art://scarf_f')));
  });

  testWidgets('партнёр сменил наряд — Ту переодевается сразу', (tester) async {
    TuWearService.instance.setPartnerOutfit(const {'neck': 'blanket'});
    await pumpCloud(tester, partner: true);
    TuWearService.instance.setPartnerOutfit(const {});
    await tester.pump();
    expect(layerUrls(tester), isEmpty, reason: 'партнёр раздел Ту');
  });

  testWidgets('партнёр наряда не присылал (старая сборка) — Ту в моём', (tester) async {
    await pumpCloud(tester, partner: true);
    expect(layerUrls(tester), contains('art://scarf_f'));
  });

  testWidgets('свой Ту — в своём наряде', (tester) async {
    TuWearService.instance.setPartnerOutfit(const {'neck': 'blanket'});
    await pumpCloud(tester, partner: false);
    expect(layerUrls(tester), contains('art://scarf_f'));
    expect(layerUrls(tester), isNot(contains('art://blanket_f')));
  });

  testWidgets('главная по умолчанию показывает Ту партнёра', (tester) async {
    SharedPreferences.setMockInitialValues({'mascot_onboarding_shown': true});
    final service = MascotService();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ActiveMascotWidget(
            mascotService: service,
            theme: buildAppTheme(kPalettes[0], Brightness.light),
            onOpenGallery: () {},
            sleepOf: (_) => const SleepWindow(from: 0, to: 0, enabled: false),
          ),
        ]),
      ),
    ));
    await tester.pump();
    service.debugSetState(const GroupMascotState(activeMascotId: kCloudMascotId, positionX: 0.5, positionY: 0.5));
    tester.binding.scheduleFrame();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.widget<CloudMascotView>(find.byType(CloudMascotView)).partnerOutfit, isTrue);
  });
}
