import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cycle_entry.dart';
import '../models/user_data.dart';
import '../utils/cycle_math.dart';
import 'cycle_repository.dart';
import 'pocketbase_service.dart';

/// Состояние календаря цикла.
///
/// Держит свои отметки и — если партнёрша разрешила — её. Прогноз считает
/// [CycleMath] по своим данным; чужой прогноз не строим, только показываем то,
/// что разрешено видеть.
///
/// Раздел доступен, когда в профиле выбран женский пол: у остальных цикла не
/// бывает, и предлагать его — шум. Отметка близости к полу не привязана, но
/// живёт в том же календаре.
class CycleService extends ChangeNotifier {
  CycleService._();
  static final CycleService instance = CycleService._();
  factory CycleService() => instance;

  static const String _kSharePref = 'cycle_share_with_partner';

  final CycleRepository _repo = CycleRepository();

  String _groupId = '';
  String _partnerUid = '';

  List<CycleEntry> _mine = const [];
  List<CycleEntry> _partner = const [];

  /// Разрешено ли партнёру видеть мои отметки. Локальная копия настройки:
  /// правда живёт в поле `shared` каждой записи на сервере.
  bool _shareWithPartner = false;

  List<CycleEntry> get mine => List.unmodifiable(_mine);
  List<CycleEntry> get partner => List.unmodifiable(_partner);
  bool get shareWithPartner => _shareWithPartner;

  /// Показывать ли раздел вообще.
  static bool availableFor(UserData? user) => user?.gender == Gender.female;

  /// Дни, когда у меня отмечены месячные, — вход для всех расчётов.
  List<DateTime> get _periodDays => _mine
      .where((e) => e.kind == CycleKind.period)
      .map((e) => e.day)
      .toList();

  /// Прогноз по своим данным. null — циклов меньше двух.
  CycleForecast? get forecast => CycleMath.predict(_periodDays);

  int? get averageCycleLength => CycleMath.averageCycleLength(_periodDays);
  int? get averagePeriodLength => CycleMath.averagePeriodLength(_periodDays);
  int? get dayOfCycle => CycleMath.dayOfCycle(_periodDays);

  /// Чем помечен день — для раскраски календаря.
  CyclePhase phaseOn(DateTime day) => CycleMath.phaseOn(_periodDays, day);

  /// Отметки на конкретный день: свои и партнёрские вперемешку.
  List<CycleEntry> entriesOn(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return [
      ..._mine.where((e) => e.day == key),
      ..._partner.where((e) => e.day == key),
    ];
  }

  /// Есть ли моя отметка такого рода в этот день.
  CycleEntry? myEntryOn(DateTime day, CycleKind kind) {
    final key = DateTime(day.year, day.month, day.day);
    for (final e in _mine) {
      if (e.day == key && e.kind == kind) return e;
    }
    return null;
  }

  Future<void> bind({required String groupId, String partnerUid = ''}) async {
    _groupId = groupId;
    _partnerUid = partnerUid;
    final prefs = await SharedPreferences.getInstance();
    _shareWithPartner = prefs.getBool(_kSharePref) ?? false;
    await refresh();
  }

  Future<void> refresh() async {
    if (_groupId.isEmpty) return;
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;

    _mine = await _repo.load(_groupId, uid);
    _partner = _partnerUid.isEmpty
        ? const []
        : await _repo.load(_groupId, _partnerUid);
    notifyListeners();
  }

  /// Ставит или снимает отметку — тап по одному и тому же дню переключает.
  Future<void> toggle(DateTime day, CycleKind kind, {CycleFlow? flow}) async {
    if (_groupId.isEmpty) return;
    final existing = myEntryOn(day, kind);
    if (existing != null) {
      await _repo.unmark(existing.id);
    } else {
      await _repo.mark(
        groupId: _groupId,
        day: day,
        kind: kind,
        flow: flow,
        // Близость — событие общее, её видят оба. Месячные — только с
        // разрешения.
        shared: kind == CycleKind.intimacy ? true : _shareWithPartner,
      );
    }
    await refresh();
  }

  /// Переключает видимость моих отметок для партнёра.
  Future<void> setShareWithPartner(bool value) async {
    _shareWithPartner = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSharePref, value);
    await _repo.setShared(groupId: _groupId, shared: value);
    await refresh();
  }

  /// Стирает все мои отметки.
  Future<void> wipe() async {
    if (_groupId.isEmpty) return;
    await _repo.wipe(_groupId);
    _mine = const [];
    notifyListeners();
    debugPrint('CycleService: отметки цикла удалены');
  }
}
