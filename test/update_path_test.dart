import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/update_service.dart';

// Юля с Honor прислала в поддержку скриншот чужого окна: «Something went wrong.
// Check that Google Play is enabled on your device…». Его рисует библиотека
// Google Play Core, приехавшая с плагином обновлений, когда установка неполная —
// базовый APK есть, а докачиваемых частей нет. Так выходит после переноса
// приложений на новый телефон, клонирования и установки APK, вытащенного из
// чужого телефона. Окно английское, закрывается кнопкой Close и уносит с собой
// приложение, так что человек остаётся ни с чем.
//
// Решение о том, куда идти за обновлением, вынесено сюда именно ради этого
// случая: развилку видно и её можно проверить, не поднимая Android.
void main() {
  group('decideUpdatePath', () {
    test('обычная установка из Play спрашивает сам Play', () {
      expect(
        decideUpdatePath(sideloaded: false, splitsMissing: false),
        UpdatePath.playStore,
      );
    });

    test('сборка с GitHub сверяется с version.json', () {
      expect(
        decideUpdatePath(sideloaded: true, splitsMissing: false),
        UpdatePath.sideload,
      );
    });

    test('битая установка из Play не пускает нас в Play Core', () {
      expect(
        decideUpdatePath(sideloaded: false, splitsMissing: true),
        UpdatePath.brokenInstall,
      );
    });

    test('у сайдлоада отсутствие частей ничего не значит', () {
      // Одиночный APK по определению не имеет докачиваемых частей, и Play Core
      // мы для него всё равно не зовём — предупреждать не о чем.
      expect(
        decideUpdatePath(sideloaded: true, splitsMissing: true),
        UpdatePath.sideload,
      );
    });
  });
}
