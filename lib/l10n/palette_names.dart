import '../services/locale_service.dart';

/// Имя готовой палитры на языке человека.
///
/// `AppTheme.name` — внутреннее русское имя, его видели все языки разом в
/// шапке предпросмотра на главной. Порядок списка — номер палитры: номер
/// живёт в `owned_themes` на сервере и не двигается. Чужой номер (своя тема,
/// палитра из будущей сборки) получает имя палитры по умолчанию.
String paletteDisplayName(int index) {
  final s = LocaleService.current;
  final names = <String>[
    s.themeNamePink,
    s.themeNamePurple,
    s.themeNameBlue,
    s.themeNamePeach,
    s.themeNameSage,
    s.themeNameMidnight,
    s.themeNameLavender,
    s.themeNameCherry,
    s.themeNameMint,
    s.themeNameSunset,
    s.themeNameMonochrome,
    s.themeNameForest,
    s.themeNameOcean,
    s.themeNameHoney,
    s.themeNameLemon,
    s.themeNameSand,
    s.themeNameAurora,
    s.themeNameBordeaux,
    s.themeNameTeal,
    s.themeNameNord,
    s.themeNameCharcoalTeal,
    s.themeNameCoffee,
    s.themeNameForestDark,
    s.themeNameGarnet,
    s.themeNameDarkHoney,
    s.themeNameHalloween,
  ];
  if (index < 0 || index >= names.length) return names[0];
  return names[index];
}
