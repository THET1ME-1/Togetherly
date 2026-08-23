// `PbDataService.updateUserProfile` — БЕЛЫЙ СПИСОК: ключ, которого в нём нет,
// выбрасывается молча, а функция отвечает успехом. Так настройка сна маскотов
// не уезжала на сервер ни разу: на проде ноль непустых `mascot_sleep` при ста
// тысячах аккаунтов, хотя в приложении оно «живёт на аккаунте».
//
// Тест сверяет обе стороны по исходникам: каждый ключ, с которым зовут
// функцию, обязан быть в списке `put(...)`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ключи, которые перечисляет сама функция: `put('ключ', 'колонка')`.
///
/// Тело запроса живёт в `userProfileRow` — `updateUserProfile` только шлёт его.
Set<String> _allowedKeys(String source) {
  final start = source.indexOf('static Map<String, dynamic> userProfileRow(');
  expect(start, greaterThan(0), reason: 'функция на месте');
  final body = source.substring(start, source.indexOf('return row;', start));
  return RegExp(r"put\('(\w+)'")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Ключи, с которыми функцию зовут по всему приложению.
Map<String, List<String>> _usedKeys(Directory lib) {
  final call = RegExp(r'updateUserProfile\(\s*[^;]*?\{(.*?)\}', dotAll: true);
  // Ключ — то, что стоит сразу после «{», запятой или условия `if (...)`.
  // Без этой границы в ключи попадала бы строка из тернарника значения
  // (`gender == Gender.male ? 'male' : 'female'`).
  final key = RegExp(r"""(?:^|[,)])\s*'(\w+)'\s*:""");
  final out = <String, List<String>>{};
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final text = file.readAsStringSync();
    for (final m in call.allMatches(text)) {
      for (final k in key.allMatches(m.group(1)!)) {
        out.putIfAbsent(k.group(1)!, () => []).add(file.path.split('/').last);
      }
    }
  }
  return out;
}

/// Ключи, которые клиент шлёт заведомо впустую.
///
/// `grantedBadges` защищён стражем `users_guard.pb.js` — наградные значки
/// выдаёт только сервер, и клиентский PATCH там отвергается осознанно
/// (см. комментарий у `UserData.grantSpecialBadge`).
const Set<String> _knowinglyDropped = {'grantedBadges'};

void main() {
  test('каждый ключ профиля доезжает до сервера, а не теряется молча', () {
    final service =
        File('lib/services/pb_data_service.dart').readAsStringSync();
    final allowed = _allowedKeys(service);
    final used = _usedKeys(Directory('lib'));

    expect(used, isNotEmpty, reason: 'вызовы функции нашлись');
    final lost = used.entries
        .where((e) => !allowed.contains(e.key) && !_knowinglyDropped.contains(e.key))
        .toList();
    expect(
      lost,
      isEmpty,
      reason: 'эти ключи выбрасываются молча: '
          '${lost.map((e) => "${e.key} (${e.value.join(", ")})").join("; ")}',
    );
  });
}
