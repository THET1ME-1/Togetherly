import 'package:flutter/foundation.dart';

import '../models/pair_jar.dart';

/// Копилка открытой пары: её держат блок сундука на главной, экран сундука и
/// строка после ролика.
///
/// Пару ставит блок сундука ([groupId]): награда за ролик уходит на сервер
/// вместе с ней, и капля падает туда, где человек сейчас. Старые сборки пару
/// не шлют, сервер тогда берёт первую живую из `group_ids`.
class PairJarService extends ChangeNotifier {
  PairJarService._();

  static final PairJarService instance = PairJarService._();

  String? groupId;
  PairJar? _jar;

  PairJar? get jar => _jar;

  /// Показ строки «+1 в копилку»: ставит `main.dart` (слой виджетов), чтобы
  /// сервис не тянул за собой интерфейс.
  void Function(PairJar jar)? onDrop;

  void apply(PairJar? jar) {
    if (jar == null) return;
    _jar = jar;
    notifyListeners();
  }

  /// Ответ награды за ролик: капля упала — обновить копилку и показать строку.
  void applyDrop(PairJar? jar) {
    if (jar == null) return;
    apply(jar);
    if (jar.added) onDrop?.call(jar);
  }

  void setBonus(int bonus) {
    final j = _jar;
    if (j == null || j.bonus == bonus) return;
    _jar = j.withBonus(bonus);
    notifyListeners();
  }

  /// Сменилась пара — прежняя копилка не её.
  void bindGroup(String id) {
    if (groupId == id) return;
    groupId = id;
    _jar = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    groupId = null;
    _jar = null;
  }
}
