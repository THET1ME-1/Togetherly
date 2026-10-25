import 'miss_you_state.dart';
import 'optimistic_count.dart';

/// Свои импульсы на экране «Скучаю», которых сервер ещё не подтвердил: общий
/// счёт и счёт по видам.
///
/// TOG-40, обращение 377 (25.10.2026): «Думаю о тебе» и «Хочу обнять» уходили,
/// но число на плитке стояло, пока не выйдешь с экрана. Надбавку держала
/// только большая кнопка, а подтверждение шло живым каналом, который у части
/// людей не работает. Сервер прибавляет любой импульс и к общему счёту, и к
/// своему виду, поэтому нажатие двигает оба числа сразу.
class MissYouPending {
  const MissYouPending({
    OptimisticCount total = const OptimisticCount(),
    Map<String, OptimisticCount> vibes = const {},
  }) : _total = total,
       _vibes = vibes;

  final OptimisticCount _total;
  final Map<String, OptimisticCount> _vibes;

  /// Общий счёт для своей пилюли под сердцем.
  int get total => _total.display;

  /// Сколько раз отправлен импульс [vibe].
  int vibe(String vibe) => _vibes[vibe]?.display ?? 0;

  /// Есть нажатия, которых сервер ещё не подтвердил.
  bool get waiting => _total.pending > 0 || _vibes.values.any((c) => c.pending > 0);

  /// Нажатие: +1 к общему счёту и к своему виду, не дожидаясь сервера.
  MissYouPending tap(String vibe, DateTime now) => MissYouPending(
    total: _total.tap(now),
    vibes: {..._vibes, vibe: (_vibes[vibe] ?? const OptimisticCount()).tap(now)},
  );

  /// Отправка сорвалась: надбавка снимается сразу.
  MissYouPending failed(String vibe) => MissYouPending(
    total: _total.failed(),
    vibes: {..._vibes, if (_vibes[vibe] case final c?) vibe: c.failed()},
  );

  /// Пришла своя запись с сервера: подтверждённое снимает надбавку, старый
  /// снимок числа назад не двигает (правило [OptimisticCount.confirm]).
  MissYouPending confirm(MissYouEntry? mine, {required DateTime now}) {
    final byVibe = mine?.byVibe ?? const <String, int>{};
    final keys = {..._vibes.keys, ...byVibe.keys};
    return MissYouPending(
      total: _total.confirm(mine?.count ?? 0, now: now),
      vibes: {
        for (final k in keys) k: (_vibes[k] ?? const OptimisticCount()).confirm(byVibe[k] ?? 0, now: now),
      },
    );
  }

  /// Надбавки, которых сервер не подтвердил за [OptimisticCount.ttl],
  /// уходят: событие либо доехало, либо не доедет вовсе.
  MissYouPending expire(DateTime now) => MissYouPending(
    total: _total.confirm(_total.confirmed, now: now),
    vibes: {for (final e in _vibes.entries) e.key: e.value.confirm(e.value.confirmed, now: now)},
  );
}
