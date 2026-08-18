/// Живой мазок в канале `draw:<группа>`: приросты вместо целой линии.
///
/// Прежде каждые 150 мс туда уходил ВЕСЬ мазок со всеми точками. Сообщение
/// росло вместе с линией, партнёр видел движение ступеньками по 150 мс, а в
/// момент отпускания линия и вовсе пропадала: живую копию снимали сразу, а
/// постоянная приходила из базы через 200–600 мс.
///
/// Теперь между ключевыми кадрами идут приросты по 40 мс — сотня байт вместо
/// килобайтов, — а ключевой кадр остаётся по двум причинам: его читают сборки
/// постарше (для них ничего не изменилось, они видят прежний `points` с
/// прежней частотой) и он чинит потерянный пакет, не дожидаясь конца мазка.
///
/// Финальный пакет несёт всю линию и номер в порядке рисования: получатель
/// кладёт мазок к себе немедленно, как обычный штрих, и ожидание базы
/// перестаёт быть видимым.
library;

import 'draw_stroke.dart';

/// Постоянные свойства мазка: их незачем слать в каждом приросте.
class LiveStrokeMeta {
  const LiveStrokeMeta({
    required this.colorValue,
    required this.strokeWidth,
    required this.isEraser,
    required this.isFilledShape,
    required this.shapeType,
  });

  final int colorValue;
  final double strokeWidth;
  final bool isEraser;
  final bool isFilledShape;
  final DrawShapeType? shapeType;

  Map<String, dynamic> toMap() => {
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'isEraser': isEraser,
        'isFilledShape': isFilledShape,
        if (shapeType != null) 'shapeType': shapeType!.name,
      };

  static LiveStrokeMeta fromMap(Map<String, dynamic> m) => LiveStrokeMeta(
        colorValue: (m['colorValue'] as num?)?.toInt() ?? 0xFF000000,
        strokeWidth: (m['strokeWidth'] as num?)?.toDouble() ?? 4.0,
        isEraser: m['isEraser'] == true,
        isFilledShape: m['isFilledShape'] == true,
        shapeType: parseShapeType(m['shapeType'] as String?),
      );
}

/// Сборка пакетов. Мета едет в каждом: она стоит полсотни байт, а без неё
/// первый же потерянный ключевой кадр красит чужую линию чужим цветом.
class LiveStrokeWire {
  const LiveStrokeWire._();

  static Map<String, dynamic> increment({
    required String sid,
    required int seq,
    required int from,
    required List<DrawPoint> points,
    required LiveStrokeMeta meta,
  }) =>
      {
        ...meta.toMap(),
        'sid': sid,
        'seq': seq,
        'from': from,
        'pts': points.map((p) => p.toMap()).toList(),
        'ts': _now(),
      };

  static Map<String, dynamic> keyframe({
    required String sid,
    required int seq,
    required List<DrawPoint> points,
    required LiveStrokeMeta meta,
  }) =>
      {
        ...meta.toMap(),
        'sid': sid,
        'seq': seq,
        'points': points.map((p) => p.toMap()).toList(),
        'ts': _now(),
      };

  static Map<String, dynamic> done({
    required String sid,
    required int seq,
    required List<DrawPoint> points,
    required LiveStrokeMeta meta,
    required int orderIndex,
  }) =>
      {
        ...meta.toMap(),
        'sid': sid,
        'seq': seq,
        'points': points.map((p) => p.toMap()).toList(),
        'orderIndex': orderIndex,
        'done': true,
        'ts': _now(),
      };

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// Состояние чужого мазка: складывает приросты, чинится ключевыми кадрами.
class LiveStrokeAssembler {
  final List<DrawPoint> _points = [];
  String? _sid;
  LiveStrokeMeta? _meta;
  bool _done = false;
  int _orderIndex = -1;

  List<DrawPoint> get points => List.unmodifiable(_points);
  String? get strokeId => _sid;
  bool get done => _done;

  void accept(Map<String, dynamic> packet) {
    final sid = (packet['sid'] ?? '').toString();

    // Старый формат: ни sid, ни приростов — только полный список точек.
    if (sid.isEmpty) {
      _sid = null;
      _done = false;
      _meta = LiveStrokeMeta.fromMap(packet);
      _replacePoints(packet['points']);
      return;
    }

    if (_sid != sid) {
      _sid = sid;
      _points.clear();
      _done = false;
      _orderIndex = -1;
    }

    _meta = LiveStrokeMeta.fromMap(packet);

    final full = packet['points'];
    if (full is List) {
      // Ключевой кадр или финал: состояние известно целиком, дыры заживают.
      _replacePoints(full);
    } else {
      final from = (packet['from'] as num?)?.toInt() ?? _points.length;
      final chunk = packet['pts'];
      // Пакет из будущего означает потерю по дороге. Выдумывать точки нельзя:
      // линия пойдёт мимо руки. Ждём ключевого кадра, он придёт через 150 мс.
      if (chunk is List && from <= _points.length) {
        final parsed = _parsePoints(chunk);
        // Повтор уже принятого куска (пакеты могут прийти дважды) отбрасываем.
        final skip = _points.length - from;
        if (skip < parsed.length) _points.addAll(parsed.sublist(skip));
      }
    }

    if (packet['done'] == true) {
      _done = true;
      _orderIndex = (packet['orderIndex'] as num?)?.toInt() ?? -1;
    }
  }

  void _replacePoints(dynamic raw) {
    _points
      ..clear()
      ..addAll(_parsePoints(raw));
  }

  List<DrawPoint> _parsePoints(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((p) => DrawPoint.fromMap(Map<String, dynamic>.from(p)))
        .toList();
  }

  /// Мазок, который партнёр ведёт прямо сейчас: рисуется поверх холста и в
  /// состав рисунка ещё не входит, поэтому номера в порядке у него нет.
  DrawStroke? buildLive(String userId) {
    final meta = _meta;
    if (meta == null || _points.isEmpty) return null;
    return DrawStroke(
      id: 'live_$userId',
      clientId: _sid,
      userId: userId,
      colorValue: meta.colorValue,
      strokeWidth: meta.strokeWidth,
      points: List.unmodifiable(_points),
      isEraser: meta.isEraser,
      isFilledShape: meta.isFilledShape,
      shapeType: meta.shapeType,
      orderIndex: -1,
    );
  }

  /// Готовый штрих партнёра — только после финального пакета.
  ///
  /// Идентификатор строится из `sid`, поэтому пришедшая позже запись из базы
  /// узнаёт этот мазок по `clientId` и заменяет его без мигания и без дубля.
  DrawStroke? buildStroke(String userId) {
    final sid = _sid;
    final meta = _meta;
    if (!_done || sid == null || meta == null || _points.isEmpty) return null;
    return DrawStroke(
      id: 'live_$sid',
      clientId: sid,
      userId: userId,
      colorValue: meta.colorValue,
      strokeWidth: meta.strokeWidth,
      points: List.unmodifiable(_points),
      isEraser: meta.isEraser,
      isFilledShape: meta.isFilledShape,
      shapeType: meta.shapeType,
      orderIndex: _orderIndex,
    );
  }

  /// Забыть мазок: партнёр отпустил палец и мы его уже зафиксировали.
  void reset() {
    _points.clear();
    _sid = null;
    _meta = null;
    _done = false;
    _orderIndex = -1;
  }
}
