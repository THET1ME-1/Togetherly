import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_palettes.dart';

/// Тема, которую человек собрал сам: цвет из фотографии или из пикера.
///
/// Хранится не палитрой, а одним цветом — палитру из него разворачивает
/// [customPalette] тем же способом, что и готовые двадцать пять. Фотография
/// никуда не уезжает: из неё берётся только этот цвет.
@immutable
class CustomTheme {
  final Color seed;
  final String name;

  const CustomTheme({required this.seed, this.name = ''});

  Map<String, dynamic> toJson() => {
        'seed': seed.toARGB32(),
        if (name.isNotEmpty) 'name': name,
      };

  /// Возвращает null, если цвета в записи нет: тема без цвета — не тема.
  static CustomTheme? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final seed = raw['seed'];
    final value = seed is num
        ? seed.toInt()
        : (seed is String ? int.tryParse(seed) : null);
    if (value == null) return null;
    final name = raw['name'];
    return CustomTheme(
      seed: Color(value),
      name: name is String ? name : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomTheme && other.seed == seed && other.name == name;

  @override
  int get hashCode => Object.hash(seed, name);

  @override
  String toString() => 'CustomTheme(${seed.toARGB32().toRadixString(16)}, $name)';
}

/// Разбор поля `users.custom_themes`.
///
/// json-поле PocketBase приезжает то строкой, то уже разобранным списком, а
/// после ручной правки на сервере — чем угодно. Кривая запись пропускается,
/// соседние остаются: настройки оформления не имеют права падать целиком
/// из-за одной строки.
List<CustomTheme> parseCustomThemes(dynamic raw) {
  dynamic value = raw;
  if (value is String) {
    if (value.trim().isEmpty) return const [];
    try {
      value = jsonDecode(value);
    } catch (_) {
      return const [];
    }
  }
  if (value is! List) return const [];
  final out = <CustomTheme>[];
  for (final item in value) {
    final theme = CustomTheme.fromJson(item);
    if (theme != null) out.add(theme);
    if (out.length == kMaxCustomThemes) break;
  }
  return out;
}

String encodeCustomThemes(List<CustomTheme> themes) =>
    jsonEncode(themes.map((t) => t.toJson()).toList());

/// Добавляет тему, пока в наборе есть место. Полный набор возвращается как был.
List<CustomTheme> addCustomTheme(List<CustomTheme> themes, CustomTheme theme) =>
    themes.length >= kMaxCustomThemes
        ? List.of(themes)
        : [...themes, theme];

List<CustomTheme> replaceCustomTheme(
    List<CustomTheme> themes, int index, CustomTheme theme) {
  if (index < 0 || index >= themes.length) return List.of(themes);
  final out = List.of(themes);
  out[index] = theme;
  return out;
}

List<CustomTheme> removeCustomTheme(List<CustomTheme> themes, int index) {
  if (index < 0 || index >= themes.length) return List.of(themes);
  final out = List.of(themes);
  out.removeAt(index);
  return out;
}

/// Какой темой красить приложение после удаления своей темы из набора.
///
/// Свои темы адресуются слотом, а слоты сдвигаются: удалили первую — вторая
/// стала первой. Без пересчёта человек, удаливший соседнюю тему, оказывался в
/// чужом цвете, а удалив выбранную — в несуществующей палитре.
int themeIdAfterRemoval(int themeId, int removedSlot) {
  if (!isCustomPaletteIndex(themeId)) return themeId;
  final slot = customPaletteSlot(themeId);
  if (slot == removedSlot) return 0;
  return slot > removedSlot ? customPaletteIndex(slot - 1) : themeId;
}

/// Палитра, которой сейчас крашено приложение.
///
/// Индекс приходит и от прежних сборок, и из prefs, и с чужого устройства,
/// где набор своих тем другой: на пропавший слот откатываемся к палитре по
/// умолчанию, а не оставляем экран без цвета.
Palette paletteFor(int themeId, List<CustomTheme> custom) {
  if (isCustomPaletteIndex(themeId)) {
    final slot = customPaletteSlot(themeId);
    if (slot < custom.length) {
      return customPalette(custom[slot].seed,
          slot: slot, name: custom[slot].name);
    }
    return paletteByIndex(0);
  }
  return paletteByIndex(themeId);
}

/// Что стоит в кружке ленты оформления.
enum StripKind { add, custom, palette }

/// Один кружок ленты «Внешний вид».
@immutable
class StripEntry {
  final StripKind kind;

  /// Слот своей темы или номер готовой палитры; у кнопки «завести» это -1.
  final int index;

  const StripEntry.add()
      : kind = StripKind.add,
        index = -1;
  const StripEntry.custom(this.index) : kind = StripKind.custom;
  const StripEntry.palette(this.index) : kind = StripKind.palette;

  bool get isPalette => kind == StripKind.palette;

  @override
  bool operator ==(Object other) =>
      other is StripEntry && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => '${kind.name}:$index';
}

/// Порядок кружков в ленте оформления: сперва «завести свою», за ней свои
/// цвета, дальше готовые палитры.
///
/// Сделанное человеком стоит первым намеренно: за двадцатью пятью готовыми
/// кружками своё пришлось бы искать прокруткой. У некупившего своих кружков
/// нет вовсе, когда Togetherly+ на этой платформе не существует (iPhone).
List<StripEntry> paletteStripEntries({
  required int customCount,
  required bool plusVisible,
}) =>
    [
      if (plusVisible) ...[
        const StripEntry.add(),
        for (var i = 0; i < customCount; i++) StripEntry.custom(i),
      ],
      for (var i = 0; i < kPalettes.length; i++) StripEntry.palette(i),
    ];
