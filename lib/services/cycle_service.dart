import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cycle_consent.dart';
import '../models/cycle_entry.dart';
import '../models/user_data.dart';
import '../utils/cycle_math.dart';
import 'cycle_repository.dart';
import 'plus_service.dart';
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
  static const String _kConsentPref = 'cycle_consent';

  final CycleRepository _repo = CycleRepository();

  String _groupId = '';
  String _partnerUid = '';

  List<CycleEntry> _mine = const [];
  List<CycleEntry> _partner = const [];

  StreamSubscription<List<CycleEntry>>? _mineSub;
  StreamSubscription<List<CycleEntry>>? _partnerSub;

  /// Разрешено ли партнёру видеть мои отметки. Локальная копия настройки:
  /// правда живёт в поле `shared` каждой записи на сервере.
  bool _shareWithPartner = false;

  List<CycleEntry> get mine => List.unmodifiable(_mine);
  List<CycleEntry> get partner => List.unmodifiable(_partner);
  bool get shareWithPartner => _shareWithPartner;

  /// Явное согласие на обработку данных цикла.
  ///
  /// Отметки цикла — особая категория персональных данных: закон Молдовы
  /// № 133/2011 и GDPR требуют отдельного согласия, а не общего «принимаю
  /// политику» при регистрации. Пока согласия нет, раздел данные не пишет.
  CycleConsent _consent = const CycleConsent.absent();
  CycleConsent get consent => _consent;
  bool get consentGranted => _consent.granted;

  Future<void> _loadConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kConsentPref);
    if (raw == null || raw.isEmpty) {
      _consent = const CycleConsent.absent();
      return;
    }
    try {
      _consent = CycleConsent.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      _consent = const CycleConsent.absent();
    }
  }

  Future<void> _saveConsent(CycleConsent value) async {
    _consent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConsentPref, jsonEncode(value.toMap()));
  }

  /// Человек согласился вести цикл в приложении.
  Future<void> grantConsent() => _saveConsent(
        CycleConsent.granted(at: DateTime.now(), version: kCycleConsentVersion),
      );

  /// Отзыв согласия. Отзывать должно быть так же просто, как соглашаться,
  /// поэтому вместе с флагом стираются и сами отметки: держать их дальше
  /// оснований нет.
  Future<void> withdrawConsent() async {
    await wipe();
    await _saveConsent(_consent.withdrawn(at: DateTime.now()));
  }

  /// Показывать ли раздел вообще.
  ///
  /// Женский пол — потому что цикла у остальных не бывает; Togetherly+ —
  /// потому что это платная часть. Раздел не прячем совсем: без покупки
  /// строка ведёт на экран Togetherly+, иначе о ней никто не узнает.
  ///
  /// Исключение — платформа, где Togetherly+ не продаётся (iOS): там
  /// некупившему раздела нет вовсе, вести его некуда. У купившего он на месте:
  /// флаг живёт на аккаунте и переезжает вместе с ним.
  static bool availableFor(UserData? user) =>
      user?.gender == Gender.female && PlusService.instance.visible;

  /// Открыт ли раздел на самом деле.
  static bool unlockedFor(UserData? user) =>
      availableFor(user) && PlusService.instance.active;

  /// Дни месячных из набора отметок. Близость в расчёт не идёт: она живёт в
  /// том же календаре, но к циклу отношения не имеет.
  static List<DateTime> _periodDaysOf(Iterable<CycleEntry> entries) => entries
      .where((e) => e.kind == CycleKind.period)
      .map((e) => e.day)
      .toList();

  /// Прогноз по любому набору отметок. Расчёт не спрашивает, чей это набор,
  /// поэтому одинаково считает и свой цикл, и цикл партнёрши, которая
  /// разрешила показывать отметки. null — циклов меньше двух.
  static CycleForecast? forecastOf(
    Iterable<CycleEntry> entries, {
    DateTime? today,
  }) =>
      CycleMath.predict(_periodDaysOf(entries), today: today);

  /// Чем помечен день у владельца [entries] — для раскраски его сетки.
  static CyclePhase phaseOf(
    Iterable<CycleEntry> entries,
    DateTime day, {
    DateTime? today,
  }) =>
      CycleMath.phaseOn(_periodDaysOf(entries), day, today: today);

  /// Дни, когда у меня отмечены месячные, — вход для всех расчётов.
  List<DateTime> get _periodDays => _periodDaysOf(_mine);

  /// Прогноз по своим данным. null — циклов меньше двух.
  CycleForecast? get forecast => CycleMath.predict(_periodDays);

  int? get averageCycleLength => CycleMath.averageCycleLength(_periodDays);
  int? get averagePeriodLength => CycleMath.averagePeriodLength(_periodDays);
  int? get dayOfCycle => CycleMath.dayOfCycle(_periodDays);

  /// Какой это день месячных (1-й, 2-й, …). null — в этот день не отмечено.
  int? periodDayIndex(DateTime day) =>
      CycleMath.periodDayIndex(_periodDays, day);

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
    await _loadConsent();
    _listen();
  }

  /// Живые подписки на свои и партнёрские отметки. Переподписываемся с нуля:
  /// bind зовётся и при смене пары.
  void _listen() {
    _mineSub?.cancel();
    _partnerSub?.cancel();
    _mineSub = null;
    _partnerSub = null;

    if (_groupId.isEmpty) return;
    final uid = PocketBaseService().userId ?? '';
    if (uid.isEmpty) return;

    _mineSub = _repo.watch(_groupId, uid).listen((entries) {
      _mine = entries;
      notifyListeners();
    });
    if (_partnerUid.isNotEmpty) {
      _partnerSub = _repo.watch(_groupId, _partnerUid).listen((entries) {
        _partner = entries;
        notifyListeners();
      });
    }
  }

  /// Разовое перечитывание — запасной путь, когда подписка ещё не поднялась.
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

  void unbind() {
    _mineSub?.cancel();
    _partnerSub?.cancel();
    _mineSub = null;
    _partnerSub = null;
    _groupId = '';
    _partnerUid = '';
    _mine = const [];
    _partner = const [];
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
    // Перечитывать не нужно: репозиторий пишет в местное хранилище, а живая
    // подписка отдаёт изменение сразу — отметка появляется без сети.
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
