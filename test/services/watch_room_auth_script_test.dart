import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/watch_room_service.dart';

/// Достаёт объект, который скрипт кладёт странице.
Map<String, dynamic> _payload(String js) {
  const mark = 'window.__togetherlyAuth=';
  final body = js.substring(js.indexOf(mark) + mark.length, js.lastIndexOf(';})();'));
  return jsonDecode(body) as Map<String, dynamic>;
}

/// С 16.09.2026 комната пары пускает только участников (к паре зашли
/// посторонние, узнавшие код). Встроенный браузер приложения доказывает
/// участие нашей сессией: без неё выпущенным после этого сборкам пришлось бы
/// входить в комнату ещё раз.
void main() {
  group('authScript', () {
    test('кладёт токен и имя туда, где их ищет room.js', () {
      final js = WatchRoomService.authScript(token: 'abc.def.ghi', name: ' Саша ');
      expect(js, contains('window.__togetherlyAuth='));
      final data = _payload(js);
      expect(data['token'], 'abc.def.ghi');
      expect(data['name'], 'Саша');
    });

    test('отдаёт сессию только своему домену', () {
      final js = WatchRoomService.authScript(token: 't');
      expect(js, contains("location.hostname!=='togetherly.day'"));
      expect(js.indexOf('hostname'), lessThan(js.indexOf('__togetherlyAuth')));
    });

    test('кавычки в имени не ломают скрипт', () {
      final js = WatchRoomService.authScript(token: 't', name: "O'Neil \"Z\" </script>");
      expect(_payload(js)['name'], "O'Neil \"Z\" </script>");
    });

    test('имя room.js и Dart совпадает', () {
      final room = File('pocketbase/pb_public/watch/room/room.js').readAsStringSync();
      expect(room, contains('window.__togetherlyAuth'));
    });
  });

  test('экран комнаты передаёт сессию странице', () {
    final src = File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    expect(src, contains('initialUserScripts'));
    expect(src, contains('WatchRoomService.authScript('));
    expect(src, contains('UserScriptInjectionTime.AT_DOCUMENT_START'));
  });
}
