import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dict_strings.dart';

/// Один вариант launcher-иконки приложения. Цвета совпадают с ассетами,
/// сгенерированными `tool/gen_app_icons.py` (фон = primaryLight темы, буквы
/// «TY» = тёмный акцент темы), чтобы превью в приложении было «как на столе».
class AppIconOption {
  final String id; // совпадает с alias-id в MainActivity.kt / манифесте
  final Color background;
  final Color letters;

  /// Значок нарисован картинкой, а не монограммой: превью тогда показывает сам
  /// ассет. Так живёт основная иконка — рисунок, который под темы не красится.
  final String? asset;

  const AppIconOption({
    required this.id,
    required this.background,
    required this.letters,
    this.asset,
  });

  /// Название живёт в словаре (`lib/l10n/dict/app_icons.dart`): язык там
  /// колонка, а не пара полей в модели.
  String get name => trKey('appicon_$id');
}

/// Смена иконки приложения через activity-alias (только Android).
///
/// На Android нет нативного «alternate icon» API: в манифесте заведены
/// `<activity-alias>` (по одному на тему), а нативный код через
/// `PackageManager.setComponentEnabledSetting` включает выбранный и гасит
/// остальные. Канал — `app_icon`, метод `setIcon`.
class AppIconService {
  AppIconService._();
  static final AppIconService instance = AppIconService._();

  static const MethodChannel _channel = MethodChannel('app_icon');
  static const String _prefKey = 'app_icon_id';
  static const String defaultId = 'default';

  /// Основная иконка плюс тринадцать монограмм под темы. Набор расширяется
  /// alias'ом в манифесте, строкой в `ICON_ALIASES` (MainActivity.kt), ассетами
  /// генератора и записью здесь.
  static const List<AppIconOption> options = [
    // Рисунок маскота: своя картинка, а не буквы цветом темы. Стоит в списке,
    // чтобы к ней можно было вернуться, выбрав однажды цветную.
    AppIconOption(
      id: 'default',
      background: Color(0xFFFDE3E2),
      letters: Color(0xFFF6493A),
      asset: 'assets/images/logo/app_icon.webp',
    ),
    AppIconOption(
      id: 'pink',
      background: Color(0xFFFEEAF1),
      letters: Color(0xFF3E1F3E),
    ),
    AppIconOption(
      id: 'purple',
      background: Color(0xFFE6E6FA),
      letters: Color(0xFF352F44),
    ),
    AppIconOption(
      id: 'blue',
      background: Color(0xFFEAF2FA),
      letters: Color(0xFF4D7099),
    ),
    AppIconOption(
      id: 'green',
      background: Color(0xFFEBF5E6),
      letters: Color(0xFF4E7649),
    ),
    AppIconOption(
      id: 'midnight',
      background: Color(0xFFE5E9F2),
      letters: Color(0xFF1B1F3A),
    ),
    AppIconOption(
      id: 'orange',
      background: Color(0xFFFDF3EE),
      letters: Color(0xFFCF7E5E),
    ),
    AppIconOption(
      id: 'lavender',
      background: Color(0xFFF5EFFB),
      letters: Color(0xFF8E6FB8),
    ),
    AppIconOption(
      id: 'cherry',
      background: Color(0xFFFBEAEF),
      letters: Color(0xFF7E2A45),
    ),
    AppIconOption(
      id: 'mint',
      background: Color(0xFFE6F7F0),
      letters: Color(0xFF4A9A80),
    ),
    AppIconOption(
      id: 'sunset',
      background: Color(0xFFFFEBE2),
      letters: Color(0xFFFF6F61),
    ),
    AppIconOption(
      id: 'monochrome',
      background: Color(0xFFEFEFEF),
      letters: Color(0xFF3A3A3A),
    ),
    AppIconOption(
      id: 'forest',
      background: Color(0xFFE4EFE5),
      letters: Color(0xFF284C32),
    ),
    AppIconOption(
      id: 'ocean',
      background: Color(0xFFE1F1F4),
      letters: Color(0xFF1F5A6E),
    ),
  ];

  /// Поддерживается ли смена иконки на текущей платформе.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Текущая выбранная иконка (из локального хранилища; дефолт — основная).
  Future<String> currentIconId() async {
    if (!isSupported) return defaultId;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultId;
  }

  /// Применяет иконку: переключает alias нативно и запоминает выбор.
  /// Возвращает true при успехе.
  Future<bool> setIcon(String id) async {
    if (!isSupported) return false;
    if (options.every((o) => o.id != id)) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setIcon', {'id': id});
      if (ok == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, id);
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      debugPrint('AppIconService.setIcon failed: ${e.message}');
      return false;
    }
  }

  /// Какие alias система считает включёнными сейчас.
  Future<List<String>> enabledIcons() async {
    if (!isSupported) return const [];
    try {
      final list = await _channel.invokeListMethod<String>('enabledIcons');
      return list ?? const [];
    } on PlatformException catch (e) {
      debugPrint('AppIconService.enabledIcons failed: ${e.message}');
      return const [];
    }
  }

  /// Приводит ярлыки в порядок: на рабочем столе должен быть ровно один.
  ///
  /// Выбранную иконку приложение включает явно, и это переживает обновление,
  /// а новый `.IconDefault` приехал включённым из манифеста — у выбиравших
  /// цветную ярлыков стало два («обновил, стало два», жалоба со снимком
  /// 16.08.2026). Правило, какой оставить, живёт в `models/app_icon_repair.dart`
  /// под тестами: выбор человека важнее нового умолчания.
  ///
  /// Зовётся при запуске. Когда всё в порядке, не трогает ничего: лишний
  /// `setComponentEnabledSetting` заставляет лаунчер перерисовать ярлык, а
  /// некоторые ещё и теряют его положение на экране.
  Future<void> repairIfNeeded() async {
    if (!isSupported) return;
    final enabled = await enabledIcons();
    if (!appIconNeedsRepair(enabled)) return;
    final saved = await currentIconId();
    final keep = appIconToKeep(
      enabled: enabled,
      // currentIconId отдаёт умолчание, когда выбора не было: для правила это
      // не то же самое, что осознанный выбор основной иконки.
      saved: enabled.contains(saved) || saved != defaultId ? saved : null,
    );
    debugPrint('AppIconService: включено $enabled, оставляем $keep');
    await setIcon(keep);
  }
}
