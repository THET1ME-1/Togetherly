import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pair_data.dart';
import '../models/pair_date.dart';
import 'pair_date_repository.dart';
import 'phone_calendar_sync.dart';

/// Даты активной пары для экранов (TOG-61): календарь настроений, лист дня,
/// «Все даты». Подписка одна на приложение — её ставит главная при смене пары,
/// и с ней же календарь телефона узнаёт о правках.
class PairDatesService extends ChangeNotifier {
  PairDatesService._();
  static final PairDatesService instance = PairDatesService._();

  String _groupId = '';
  StreamSubscription<List<PairDate>>? _sub;
  List<PairDate> _own = const [];

  String get groupId => _groupId;

  /// Свои даты пары, без готовых.
  List<PairDate> get own => _own;

  /// Подписаться на даты пары [groupId]; пусто — пары нет, дат нет.
  void bind(String groupId) {
    if (groupId == _groupId) return;
    _sub?.cancel();
    _sub = null;
    _own = const [];
    _groupId = groupId;
    notifyListeners();
    if (groupId.isEmpty) return;
    _sub = PairDateRepository.instance.watch(groupId).listen((dates) {
      _own = dates;
      notifyListeners();
      PhoneCalendarSync.instance.mirror(dates);
    });
  }

  /// Свои даты и готовые: годовщина пары и дни рождения обоих. Без пары —
  /// ничего: даты одиночки застряли бы в одиночной группе (урок TOG-84).
  List<PairDate> allFor(PairData pair, {required String myUid}) {
    if (!pair.isPaired) return const [];
    final names = {for (final p in pair.partners) p.uid: p.name};
    final birthdays = pair.manager.activeConnection?.memberBirthdays ?? const <String, DateTime>{};
    return [
      ..._own,
      ...autoDates(start: pair.startDate, birthdays: birthdays, myUid: myUid, names: names),
    ];
  }
}
