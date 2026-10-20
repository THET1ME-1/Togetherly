/// Правка таймера пары, которая ещё не дошла до сервера.
///
/// Обращение 358 (20.10.2026): дату на главном круге ставили, а через десять
/// минут там снова стоял день соединения. Правка уходила одной попыткой, отказ
/// никто не видел, и следующее обновление пары с сервера возвращало старую
/// дату. Теперь правка лежит на телефоне, пока сервер не вернёт то же значение,
/// и обновление пары её не откатывает.
library;

import 'timer_item.dart';

/// Вставить или заменить таймер в серверном списке по id. Основной таймер у
/// пары один, поэтому новый основной снимает флаг с остальных.
List<dynamic> upsertTimerJson(List<dynamic> list, Map<String, dynamic> timer) {
  final out = [for (final e in list) e is Map ? Map<String, dynamic>.from(e) : e];
  final index = out.indexWhere((e) => e is Map && e['id'] == timer['id']);
  if (index >= 0) {
    out[index] = timer;
  } else {
    out.add(timer);
  }
  if (timer['isDefault'] == true) {
    for (final e in out) {
      if (e is Map && e['id'] != timer['id']) e['isDefault'] = false;
    }
  }
  return out;
}

/// Таймеры с сервера, где неотправленные правки стоят поверх серверных.
List<TimerItem> mergeWithPending(List<TimerItem> remote, Map<String, TimerItem> pending) {
  final out = [for (final timer in remote) pending[timer.id]?.copyWith() ?? timer];
  for (final timer in pending.values) {
    if (!out.any((t) => t.id == timer.id)) out.add(timer.copyWith());
  }
  final main = {for (final t in pending.values) if (t.isDefault) t.id};
  if (main.isNotEmpty) {
    for (final timer in out) {
      if (!main.contains(timer.id)) timer.isDefault = false;
    }
  }
  return out;
}

/// Правки, которых на сервере ещё нет. Сервер вернул то же значение — правка
/// дошла и больше не ждёт.
Map<String, TimerItem> stillPending(List<TimerItem> remote, Map<String, TimerItem> pending) {
  final left = <String, TimerItem>{};
  pending.forEach((id, edit) {
    final same = remote.any((timer) => timer.id == id && sameTimer(timer, edit));
    if (!same) left[id] = edit;
  });
  return left;
}

bool sameTimer(TimerItem a, TimerItem b) =>
    a.title == b.title &&
    a.emoji == b.emoji &&
    a.isDefault == b.isDefault &&
    a.isCountdown == b.isCountdown &&
    a.startDate.isAtSameMomentAs(b.startDate);
