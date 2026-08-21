import 'dart:async';

import '../models/draw_stroke.dart';
import 'centrifugo_service.dart';
import 'pb_data_service.dart';
import 'pb_realtime_service.dart';

/// Один пакет живого мазка: чей он и что в нём. `data == null` — мазок снят.
class LivePacket {
  const LivePacket({required this.uid, required this.data});

  final String uid;
  final Map<String, dynamic>? data;
}

/// Срез мета холста (bg/очистка/раскраска) для draw_screen — замена
/// `RemoteCanvasMeta` из firebase_service (ноль Firebase). 0 трактуем как «не
/// задано»→null (PB number-колонки дефолтят в 0; реальные значения: bgColor —
/// ARGB>0, clearVersion — epoch-ms).
///
/// Поворота листа тут нет намеренно: как человек держит лист — его личное дело,
/// колонка `canvas_rotation` осталась только ради старых сборок, которые в неё
/// ещё пишут (см. `_onCanvasMeta` в `draw_screen`).
class CanvasMetaUpdate {
  final int? bgColor;
  final int? clearVersion;

  /// Раскраска вдвоём: какая картинка лежит контуром поверх холста, в каком
  /// режиме её красят и кто уже нажал «Готово» (uid → true).
  final String? coloringId;
  final String? coloringMode;

  /// Половины поменяны местами: на картинке бывает мальчик слева и девочка
  /// справа, и порядок uid об этом не знает — пара меняется сама.
  final bool? coloringSwap;
  final Map<String, dynamic>? coloringDone;

  const CanvasMetaUpdate({
    this.bgColor,
    this.clearVersion,
    this.coloringId,
    this.coloringMode,
    this.coloringSwap,
    this.coloringDone,
  });
}

/// Репозиторий холста-рисования поверх PocketBase (миграция §3).
///
/// Две части: КАТАЛОГ холстов (`canvas_catalogue`, метаданные списка) — для
/// `CanvasStorageService`; и САМО рисование (`canvas_strokes` committed +
/// `canvas_live` in-progress + `canvas_meta` bg/rotation/clear) — для draw_screen.
/// Чтения на PB бесплатны → всё live без лимитов. Presence НЕ переносим — она
/// была write-only (нигде не читалась). Картинки-вставки (uploadFile) — медиа §4.
class CanvasRepository {
  CanvasRepository._();
  static final CanvasRepository instance = CanvasRepository._();
  factory CanvasRepository() => instance;

  final PbDataService _data = PbDataService();
  final PbRealtimeService _rt = PbRealtimeService();

  // ── Каталог холстов ────────────────────────────────────────────────────────
  /// Живой каталог в форме, которую ждёт `CanvasStorageService._mergeRemoteCanvases`:
  /// {id, name, createdAt(ms), updatedAt(ms)}. id холста — в колонке canvas_id.
  Stream<List<Map<String, dynamic>>> watchCatalogue(String groupId) =>
      _rt.watchCanvasCatalogue(groupId).map((recs) => recs
          .map((r) => {
                'id': (r.data['canvas_id'] ?? '').toString(),
                'name': (r.data['name'] ?? '').toString(),
                'createdAt': (r.data['created_at'] as num?)?.toInt() ?? 0,
                'updatedAt': (r.data['updated_at'] as num?)?.toInt() ?? 0,
                // Размер пиксельной сетки: партнёр должен открыть холст ровно
                // с той же сеткой, иначе клетки не совпадут.
                'pixelW': (r.data['pixel_w'] as num?)?.toInt(),
                'pixelH': (r.data['pixel_h'] as num?)?.toInt(),
              })
          .where((m) => (m['id'] as String).isNotEmpty)
          .toList());

  Future<void> upsertCatalogue(
    String groupId,
    String canvasId, {
    required String name,
    required int createdAt,
    required int updatedAt,
    String? createdBy,
    int? pixelW,
    int? pixelH,
  }) =>
      _data.upsertCanvasCatalogue(groupId, canvasId, {
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': ?createdBy,
        'pixelW': ?pixelW,
        'pixelH': ?pixelH,
      });

  Future<void> renameCatalogue(String groupId, String canvasId, String name) =>
      _data.upsertCanvasCatalogue(groupId, canvasId, {
        'name': name,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> deleteCatalogue(String groupId, String canvasId) =>
      _data.deleteCanvasCatalogue(groupId, canvasId);

  Future<void> incrementDrawings(String groupId, int by) =>
      _data.incrementGroupCounter(groupId, 'drawings_count', by);

  // ── Рисование: committed-штрихи ──────────────────────────────────────────
  /// Живые штрихи холста (по order_index). Замена listenToDrawingStrokes.
  Stream<List<DrawStroke>> watchStrokes(String groupId, String canvasId) =>
      _rt.watchCanvasStrokes(groupId, canvasId).map(
          (recs) => recs.map(DrawStroke.fromPb).toList());

  /// Начало холста для плитки в галерее: первые штрихи по порядку рисования.
  Future<List<DrawStroke>> previewStrokes(
    String groupId,
    String canvasId, {
    int limit = 400,
  }) async {
    final recs =
        await _data.loadStrokesPage(groupId, canvasId, limit: limit);
    return recs.map(DrawStroke.fromPb).toList();
  }

  /// Коммит штриха (server-id). Возвращает id записи (для оптимистичного
  /// сопоставления в draw_screen) или ''.
  Future<String> addStroke(
      String groupId, String canvasId, Map<String, dynamic> data) async {
    final rec = await _data.createStroke(groupId, canvasId, data);
    return rec?.id ?? '';
  }

  Future<void> patchStroke(String strokeId, Map<String, dynamic> updates) =>
      _data.patchStroke(strokeId, updates);

  /// Отдаёт результат, а не проглатывает его: отмена штриха обязана знать,
  /// дошла ли она до сервера. Пока метод возвращал `void`, неудачное удаление
  /// терялось молча — штрих исчезал с экрана, оставался в базе и возвращался
  /// при следующей загрузке («отменённые штрихи восстанавливаются»).
  Future<bool> deleteStroke(String strokeId) => _data.deleteStroke(strokeId);

  Future<void> clear(
    String groupId,
    String canvasId, {
    required int clearVersion,
    int? bgColor,
  }) =>
      _data.clearCanvas(groupId, canvasId, clearVersion, bgColor: bgColor);

  // ── Рисование: мета (bg/очистка/раскраска) ────────────────────────────────
  Stream<CanvasMetaUpdate> watchMeta(String groupId, String canvasId) =>
      _rt.watchCanvasMeta(groupId, canvasId).map((rows) {
        if (rows.isEmpty) return const CanvasMetaUpdate();
        final d = rows.first.data;
        int? nz(dynamic v) {
          final n = (v as num?)?.toInt() ?? 0;
          return n == 0 ? null : n;
        }

        final done = d['coloring_done'];
        return CanvasMetaUpdate(
          bgColor: nz(d['bg_color']),
          clearVersion: nz(d['clear_version']),
          coloringId: (d['coloring_id'] as String?)?.trim(),
          coloringMode: (d['coloring_mode'] as String?)?.trim(),
          coloringSwap: d['coloring_swap'] == true,
          coloringDone: done is Map ? Map<String, dynamic>.from(done) : null,
        );
      });

  Future<void> setBgColor(String groupId, String canvasId, int color) =>
      _data.upsertCanvasMeta(groupId, canvasId, bgColor: color);

  /// Заводит на холсте раскраску: картинка и режим одни на двоих.
  Future<void> setColoring(
    String groupId,
    String canvasId, {
    required String pictureId,
    required String mode,
  }) =>
      _data.upsertCanvasMeta(groupId, canvasId,
          coloringId: pictureId, coloringMode: mode, coloringDone: const {});

  /// Отмечает готовность одного из двоих. Карта целиком, а не поле: правку
  /// одного ключа PocketBase в json-поле не умеет.
  /// Поменять половины местами — у обоих сразу.
  Future<void> setColoringSwap(
    String groupId,
    String canvasId, {
    required bool swapped,
  }) =>
      _data.upsertCanvasMeta(groupId, canvasId, coloringSwap: swapped);

  Future<void> setColoringDone(
    String groupId,
    String canvasId,
    Map<String, dynamic> done,
  ) =>
      _data.upsertCanvasMeta(groupId, canvasId, coloringDone: done);

  // ── Рисование: live-штрихи (in-progress) — ЭФЕМЕРНО через Centrifugo ───────
  // НЕ пишем в БД: раньше каждый in-progress штрих = запись в коллекцию
  // canvas_live → шторм на единственном SQLite-writer'е. Теперь публикуем и
  // слушаем НАПРЯМУЮ через Centrifugo (канал draw:<groupId>): ноль нагрузки на
  // БД, ниже задержка, рисование плавнее. Финальные штрихи как и прежде идут в
  // canvas_strokes (durable). liveData — карта `DrawStroke.toLiveMap()`.
  String _liveChannel(String groupId) => 'draw:$groupId';

  /// Пакеты живого мазка партнёров: каждый по отдельности, в порядке прихода.
  ///
  /// Карта состояния (см. [watchLive]) годилась, пока в канал ездил весь мазок
  /// целиком: достаточно было последнего снимка. С приростами так нельзя —
  /// пропустишь пакет, и линия потеряет кусок, — поэтому подписчик видит каждое
  /// сообщение. `data == null` означает, что мазок снят (надгробие).
  Stream<LivePacket> watchLivePackets(
      String groupId, String canvasId, String myUid) {
    RtUnsub? unsub;
    late StreamController<LivePacket> ctrl;
    ctrl = StreamController<LivePacket>.broadcast(
      onListen: () async {
        unsub = await CentrifugoService.instance
            .subscribeRaw(_liveChannel(groupId), (m) {
          final uid = (m['uid'] ?? '').toString();
          if (uid.isEmpty || uid == myUid) return;
          if ((m['canvasId'] ?? '').toString() != canvasId) return;
          final data = m['data'];
          if (ctrl.isClosed) return;
          ctrl.add(LivePacket(
            uid: uid,
            data: data is Map ? Map<String, dynamic>.from(data) : null,
          ));
        });
      },
      onCancel: () async {
        await unsub?.call();
        unsub = null;
      },
    );
    return ctrl.stream;
  }

  /// Опубликовать свой in-progress штрих (эфемерно, мимо БД).
  Future<void> setLive(String groupId, String canvasId, String uid,
          Map<String, dynamic> liveData) =>
      CentrifugoService.instance.publish(_liveChannel(groupId),
          {'uid': uid, 'canvasId': canvasId, 'data': liveData});

  /// Снять свой in-progress штрих (надгробие data:null).
  Future<void> clearLive(String groupId, String canvasId, String uid) =>
      CentrifugoService.instance.publish(_liveChannel(groupId),
          {'uid': uid, 'canvasId': canvasId, 'data': null});
}
