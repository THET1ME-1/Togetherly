/// Пауза перед новой попыткой записи, которая только что не удалась.
///
/// Вечером 13 августа 2026 сервер встал именно на этом. У кого пустовал список
/// пар, тот не видел собственную запись: правила читают членство из
/// `users.group_ids`, поиск отвечал 404, клиент шёл создавать, уникальный
/// индекс отвечал отказом — и круг повторялся каждые несколько секунд. За
/// десять минут это дало 1152 отказа «Value must be unique» и 1084 запроса
/// дольше пяти секунд; единственный писатель SQLite захлебнулся, и люди увидели
/// «сервер не отвечает».
///
/// Лечится не на сервере: клиент обязан отступать сам. Первая неудача — две
/// секунды тишины, дальше вдвое, потолок пять минут. Успех обнуляет счёт.
library;

/// Сколько молчать после [failures] неудач подряд.
Duration upsertBackoffFor(int failures) {
  if (failures <= 0) return Duration.zero;
  final capped = failures > 8 ? 8 : failures;
  final seconds = 1 << capped; // 2, 4, 8, 16, 32, 64, 128, 256
  return Duration(seconds: seconds > 300 ? 300 : seconds);
}

/// Помнит, каким записям сейчас нельзя стучаться на сервер.
///
/// Ключ тот же, что у `UpsertIdCache`: коллекция плюс фильтр. Часы передаются
/// параметром, иначе тест на паузы пришлось бы ждать по-настоящему.
class UpsertBackoff {
  final Map<String, int> _failures = {};
  final Map<String, DateTime> _quietUntil = {};

  /// Можно ли сейчас пробовать запись по этому ключу.
  bool allows(String key, {required DateTime now}) {
    final until = _quietUntil[key];
    if (until == null) return true;
    if (now.isBefore(until)) return false;
    _quietUntil.remove(key);
    return true;
  }

  /// Записать неудачу и назначить паузу.
  void failed(String key, {required DateTime now}) {
    final n = (_failures[key] ?? 0) + 1;
    _failures[key] = n;
    _quietUntil[key] = now.add(upsertBackoffFor(n));
  }

  /// Запись прошла — забываем всё про этот ключ.
  void succeeded(String key) {
    _failures.remove(key);
    _quietUntil.remove(key);
  }

  /// Смена аккаунта: чужие паузы новому человеку не наследуются.
  void clear() {
    _failures.clear();
    _quietUntil.clear();
  }

  int failuresOf(String key) => _failures[key] ?? 0;
}
