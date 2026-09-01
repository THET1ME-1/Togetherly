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
        decideUpdatePath(
          sideloaded: false,
          splitsMissing: false,
          playServices: true,
        ),
        UpdatePath.playStore,
      );
    });

    test('сборка с GitHub сверяется с version.json', () {
      expect(
        decideUpdatePath(
          sideloaded: true,
          splitsMissing: false,
          playServices: true,
        ),
        UpdatePath.sideload,
      );
    });

    test('битая установка из Play не пускает нас в Play Core', () {
      expect(
        decideUpdatePath(
          sideloaded: false,
          splitsMissing: true,
          playServices: true,
        ),
        UpdatePath.brokenInstall,
      );
    });

    test('у сайдлоада отсутствие частей ничего не значит', () {
      // Одиночный APK по определению не имеет докачиваемых частей, и Play Core
      // мы для него всё равно не зовём — предупреждать не о чем.
      expect(
        decideUpdatePath(
          sideloaded: true,
          splitsMissing: true,
          playServices: true,
        ),
        UpdatePath.sideload,
      );
    });

    // Honor и Huawei без сервисов Google — и любой телефон, где Play
    // отключён. Play Core там не работает и на вызов отвечает своим окном
    // «Check that Google Play is enabled on your device», хотя установка целая
    // и переустановка ничего не меняет. Спрашивать его нечего.
    test('без сервисов Google Play Core не зовём вовсе', () {
      expect(
        decideUpdatePath(
          sideloaded: false,
          splitsMissing: false,
          playServices: false,
        ),
        UpdatePath.none,
      );
    });

    test('целая установка без сервисов молчит, а не жалуется на части', () {
      // Разные беды: части на месте, отсутствует сам Play. Гнать человека
      // переустанавливать исправное приложение здесь нельзя.
      expect(
        decideUpdatePath(
          sideloaded: false,
          splitsMissing: true,
          playServices: false,
        ),
        UpdatePath.none,
      );
    });

    test('сайдлоаду сервисы Google не нужны', () {
      // Обновление он берёт с GitHub, Play Core не участвует.
      expect(
        decideUpdatePath(
          sideloaded: true,
          splitsMissing: false,
          playServices: false,
        ),
        UpdatePath.sideload,
      );
    });
  });
}
