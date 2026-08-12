import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож пропавших виджетов.
///
/// iOS требует, чтобы у расширения версия и номер сборки совпадали с самим
/// приложением. У нашего виджет-расширения было зашито `1.0 (1)`, пока
/// приложение шло как `1.24.0 (185)` — система такое расширение не
/// регистрирует, и в галерее виджетов Togetherly просто нет. Со стороны это
/// выглядит как «виджетов нету, они не работают», причём сборка проходит
/// молча и App Store принимает.
///
/// Версии обязаны приходить из тех же переменных, что у Runner, а для этого
/// расширению нужен доступ к `Generated.xcconfig` — иначе переменные пустые.
void main() {
  final project =
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  /// Куски настроек, относящиеся к виджет-расширению.
  List<String> widgetConfigs() {
    final blocks = project.split(RegExp(r'\n\t\t[0-9A-F]{24} /\* (?:Debug|Release|Profile) \*/ = \{'));
    return blocks
        .where((b) => b.contains('com.togetherly.love.TogetherlyWidget'))
        .toList();
  }

  test('расширение виджетов есть в проекте', () {
    expect(widgetConfigs(), isNotEmpty,
        reason: 'таргет расширения пропал из проекта');
  });

  test('версия расширения берётся из версии приложения', () {
    for (final config in widgetConfigs()) {
      expect(config, contains(r'MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"'),
          reason: 'зашитая версия расширения не даёт iOS его зарегистрировать');
      expect(
          config, contains(r'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"'),
          reason: 'номер сборки расширения обязан совпадать с приложением');
    }
  });

  test('расширению доступны переменные Flutter', () {
    for (final config in widgetConfigs()) {
      expect(config, contains('Generated.xcconfig'),
          reason: 'без этого FLUTTER_BUILD_NAME пустой, и версия обнулится');
    }
  });
}
