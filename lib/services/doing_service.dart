import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';

import '../dict_strings.dart';
import '../models/cloud_mascot.dart';
import '../models/doing.dart';
import 'catalog_service.dart';
import 'doing_widget_keys.dart';
import 'home_widget_service.dart';
import 'locale_service.dart';
import 'offline/media_view_cache.dart';
import 'pb_data_service.dart';
import 'pocketbase_service.dart';

/// Виджет «Чем заняты»: запись своего занятия и цвета комнатки на сервер и
/// раскладка данных обеих половин туда, где их читает рабочий стол.
///
/// Устроено как заметка на двоих (`HomeWidgetService.syncNote`): у каждого
/// своя запись `widget_data`, занятие лежит в её поле `data`. Правка записи
/// сама шлёт событие в канал пары и будит телефон партнёра тихим пушем.
class DoingService {
  DoingService._();

  static final DoingService instance = DoingService._();

  static const _providers = ['DoingWidgetProvider'];

  /// За запуск справочник занятий уезжает нативу один раз на язык.
  String? _catalogSentFor;

  /// Ставит своё занятие. `false` — сервер не ответил, ничего не изменилось.
  Future<bool> saveDoing(String groupId, Doing doing) =>
      _saveData(groupId, (data) => withDoing(data, doing));

  /// Красит свою комнатку. `null` — вернуть цвет темы.
  Future<bool> saveRoomColor(String groupId, Color? wall) =>
      _saveData(groupId, (data) => withRoom(data, wall));

  Future<bool> _saveData(
    String groupId,
    Map<String, dynamic> Function(Map<dynamic, dynamic> data) change,
  ) async {
    if (groupId.isEmpty || groupId == 'solo') return false;
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return false;

    try {
      // Читаем своё `data` целиком: в нём живут заметка и цвет, а запись
      // перезаписывает поле json целиком. Без связи не пишем вовсе.
      final existing = await PbDataService().loadWidgetOrThrow(groupId, uid);
      final raw = existing?.data['data'];
      final data = change(raw is Map ? raw : const {});
      final saved = await PbDataService().upsertWidget(groupId, uid, {'data': data});
      await sync(groupId);
      return saved;
    } catch (e) {
      debugPrint('DoingService: занятие не сохранилось — $e');
      return false;
    }
  }

  /// Обе половины пары с сервера: занятие и цвет комнатки каждого.
  ///
  /// [records] — записи виджетов пары, если их уже прочитал сосед (заметка на
  /// двоих читает те же): второй запрос за тем же самым не нужен.
  Future<({DoingRoom? my, DoingRoom? partner})> load(String groupId, {List<RecordModel>? records}) async {
    final uid = PocketBaseService().userId ?? '';
    if (groupId.isEmpty || groupId == 'solo' || uid.isEmpty) return (my: null, partner: null);

    DoingRoom? my, partner;
    for (final record in records ?? await PbDataService().loadWidgetsForGroup(groupId)) {
      final data = record.data['data'];
      final room = DoingRoom(
        doing: Doing.fromData(data),
        wall: roomColorOf(data),
        avatarUrl: (record.data['avatar_url'] ?? '').toString(),
      );
      if ((record.data['user_uid'] ?? '').toString() == uid) {
        my = room;
      } else {
        partner ??= room;
      }
    }
    return (my: my, partner: partner);
  }

  /// Раскладывает данные пары по ключам виджета и будит его.
  ///
  /// Зовут из приложения и из фона (тихий пуш). В фоне каталога и языка нет,
  /// поэтому подписи и ссылки на кадры берутся из справочника, записанного
  /// раньше, а не собираются заново.
  Future<void> sync(String groupId, {List<RecordModel>? records}) async {
    if (groupId.isEmpty || groupId == 'solo') return;
    try {
      final rooms = await load(groupId, records: records);
      await _rememberCatalog();

      final my = await _half(rooms.my, 'my', groupId);
      final partner = await _half(rooms.partner, 'partner', groupId);

      // Кадры: покой нужен всегда, занятия — только те, что сейчас на столе.
      final wanted = <String>{
        kDoingIdle,
        if (rooms.my?.doing.artKey != null) rooms.my!.doing.id,
        if (rooms.partner?.doing.artKey != null) rooms.partner!.doing.id,
      };
      for (final id in wanted) {
        await _artPath(id);
      }

      final keys = doingWidgetKeys(groupId: groupId, my: my, partner: partner);
      for (final entry in keys.entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await _wakeWidgets();
    } catch (e) {
      debugPrint('DoingService.sync не справился: $e');
    }
  }

  Future<DoingHalf?> _half(DoingRoom? room, String side, String groupId) async {
    if (room == null) return null;
    final avatar = room.avatarUrl.isEmpty
        ? ''
        : await HomeWidgetService.instance
            .cacheWidgetPhoto(room.avatarUrl, 'doing_avatar_${side}_$groupId', maxSide: 200);
    return DoingHalf(doing: room.doing, wall: room.wall, avatarPath: avatar);
  }

  /// Справочник для натива: подписи занятий на языке человека и ссылки на
  /// неподвижные кадры. Только строки, без загрузок. В фоне каталог пуст —
  /// тогда остаётся записанное приложением раньше.
  Future<void> _rememberCatalog() async {
    final catalog = CatalogService.instance;
    if (catalog.giftArt('act_${kDoingIds.first}') == null) return;
    final sentFor = LocaleService.instance.language.code;
    if (_catalogSentFor == sentFor) return;

    for (final id in kDoingIds) {
      await HomeWidget.saveWidgetData<String>(doingNameKey(id), trKey('doing.$id'));
      final url = catalog.giftArt('act_$id')?.stillUrl ?? '';
      if (url.isNotEmpty) await HomeWidget.saveWidgetData<String>(doingArtUrlKey(id), url);
    }
    final idle = catalog.giftArt(kCloudIdleArtKey);
    final idleUrl = idle?.stillUrl ?? idle?.lgUrl ?? '';
    if (idleUrl.isNotEmpty) await HomeWidget.saveWidgetData<String>(doingArtUrlKey(kDoingIdle), idleUrl);
    _catalogSentFor = sentFor;
  }

  /// Кадр занятия файлом, который видит виджет. Качается один раз и только
  /// для занятий, которые сейчас показывает стол.
  Future<String> _artPath(String id) async {
    final known = await HomeWidget.getWidgetData<String>(doingArtKey(id)) ?? '';
    if (known.isNotEmpty && File(known).existsSync()) return known;

    final url = await HomeWidget.getWidgetData<String>(doingArtUrlKey(id)) ?? '';
    if (url.isEmpty) return '';
    try {
      final cache = OfflineImageCacheManager.instance;
      final hit = await cache.getFileFromCache(url) ?? await cache.downloadFile(url, key: url);

      // Кадр кладём PNG как есть: у него прозрачный фон, а общий кэш фото
      // виджетов пережимает всё в JPEG.
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/doing_widget')
        ..createSync(recursive: true);
      final file = await hit.file.copy('${dir.path}/$id.png');
      final shared = await HomeWidgetService.instance.appGroupReadablePath(file.path, 'doing_$id.png');
      if (shared.isNotEmpty) await HomeWidget.saveWidgetData<String>(doingArtKey(id), shared);
      return shared;
    } catch (e) {
      debugPrint('DoingService: кадр $id не скачался — $e');
      return '';
    }
  }

  Future<void> _wakeWidgets() async {
    for (final name in _providers) {
      await HomeWidget.updateWidget(
        name: name,
        androidName: name,
        qualifiedAndroidName: 'com.togetherly.love.$name',
      );
    }
  }
}

/// Одна половина, как она лежит на сервере.
class DoingRoom {
  const DoingRoom({required this.doing, this.wall, this.avatarUrl = ''});

  final Doing doing;
  final Color? wall;
  final String avatarUrl;
}
