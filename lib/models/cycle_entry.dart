import 'package:pocketbase/pocketbase.dart';

/// Что отмечено в этот день.
enum CycleKind {
  /// Идут месячные.
  period,

  /// Близость. К циклу отношения не имеет, но живёт в том же календаре —
  /// удобнее, когда обе отметки в одном месте.
  intimacy,
}

/// Обильность выделений. Нужна для дневника, в прогнозе не участвует.
enum CycleFlow { light, medium, heavy }

/// Отметка в календаре цикла.
///
/// Данные чувствительные, поэтому у каждой записи есть [shared]: пока он
/// выключен, запись не отдаётся партнёру самим сервером — правило чтения
/// коллекции смотрит именно на это поле, а не на настройку в интерфейсе.
class CycleEntry {
  const CycleEntry({
    required this.id,
    required this.day,
    required this.kind,
    this.flow,
    this.shared = false,
    this.userUid = '',
  });

  final String id;

  /// День отметки, нормализованный к началу суток.
  final DateTime day;

  final CycleKind kind;
  final CycleFlow? flow;
  final bool shared;

  /// Чья отметка. Для близости показывается обоим, для месячных — автору и,
  /// если разрешено, партнёру.
  final String userUid;

  static CycleKind kindFromStorage(String? raw) =>
      raw == 'intimacy' ? CycleKind.intimacy : CycleKind.period;

  static String kindToStorage(CycleKind kind) =>
      kind == CycleKind.intimacy ? 'intimacy' : 'period';

  static CycleFlow? flowFromStorage(String? raw) => switch (raw) {
        'light' => CycleFlow.light,
        'medium' => CycleFlow.medium,
        'heavy' => CycleFlow.heavy,
        _ => null,
      };

  static String? flowToStorage(CycleFlow? flow) => switch (flow) {
        CycleFlow.light => 'light',
        CycleFlow.medium => 'medium',
        CycleFlow.heavy => 'heavy',
        null => null,
      };

  factory CycleEntry.fromPb(RecordModel rec) {
    final rawDay = rec.getStringValue('day');
    final parsed = DateTime.tryParse(rawDay)?.toLocal() ?? DateTime.now();
    return CycleEntry(
      id: rec.id,
      day: DateTime(parsed.year, parsed.month, parsed.day),
      kind: kindFromStorage(rec.getStringValue('kind')),
      flow: flowFromStorage(rec.getStringValue('flow')),
      shared: rec.getBoolValue('shared'),
      userUid: rec.getStringValue('user_uid'),
    );
  }

  factory CycleEntry.fromMap(Map<String, dynamic> map) {
    final parsed =
        DateTime.tryParse((map['day'] ?? '') as String)?.toLocal() ??
            DateTime.now();
    return CycleEntry(
      id: (map['id'] ?? '') as String,
      day: DateTime(parsed.year, parsed.month, parsed.day),
      kind: kindFromStorage(map['kind'] as String?),
      flow: flowFromStorage(map['flow'] as String?),
      shared: (map['shared'] as bool?) ?? false,
      userUid: (map['user_uid'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap({required String groupId}) => {
        'id': id,
        'group_id': groupId,
        'user_uid': userUid,
        'day': day.toIso8601String(),
        'kind': kindToStorage(kind),
        if (flowToStorage(flow) != null) 'flow': flowToStorage(flow),
        'shared': shared,
      };

  CycleEntry copyWith({CycleFlow? flow, bool? shared}) => CycleEntry(
        id: id,
        day: day,
        kind: kind,
        flow: flow ?? this.flow,
        shared: shared ?? this.shared,
        userUid: userUid,
      );
}
