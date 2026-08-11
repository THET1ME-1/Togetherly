import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'app_theme.dart';

/// Единая модель тем: палитра (акцент) × режим (свет/тьма) × вариант × AMOLED.
///
/// Раньше было 25 захардкоженных [AppTheme] — часть «светлые», часть «тёмные».
/// Теперь палитра — это ОДИН акцент, а свет/тьма — отдельный бесплатный тумблер.
/// Любой акцент раскрывается в обоих режимах через M3 ([ColorScheme.fromSeed]),
/// а узнаваемость («розовая — розовая») ведёт сам акцент, не производный tertiary.

/// Режим: светлый, тёмный, как в системе. Бесплатный тумблер поверх палитры.
enum AppThemeMode { light, dark, system }

extension AppThemeModeX on AppThemeMode {
  /// Разрешить в конкретную яркость. Для [system] берётся текущая яркость ОС.
  Brightness resolve() => switch (this) {
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
        AppThemeMode.system =>
          PlatformDispatcher.instance.platformBrightness,
      };
}

/// Вариант схемы: мягкий (по умолчанию), «сочно», «точь-в-точь».
enum SchemeFlavor { soft, juicy, exact }

extension SchemeFlavorX on SchemeFlavor {
  DynamicSchemeVariant get variant => switch (this) {
        SchemeFlavor.soft => DynamicSchemeVariant.tonalSpot,
        SchemeFlavor.juicy => DynamicSchemeVariant.vibrant,
        SchemeFlavor.exact => DynamicSchemeVariant.fidelity,
      };
}

/// Цель палитры: за именем стоит вещь, а у вещи свой оттенок, своя светлота и
/// своя мера насыщенности.
///
/// Одного акцента для этого мало. Схема M3 берёт из сида ТОЛЬКО оттенок, а
/// хрому и тон назначает сама — у всех 25 палитр выходило ровно 36 и 40. При
/// тоне 40 персик физически не может быть персиком: получается коричневый.
/// Розовая и вишнёвая при этом различались на четыре градуса оттенка, то есть
/// не различались вовсе (жалобы 8 августа 2026).
///
/// [hue] и [tone] задаёт предмет, [k] — доля от предельной насыщенности,
/// достижимой в sRGB на этой паре. Единица = край экрана. Ниже единицы —
/// сознательно приглушённые: песок не бывает кислотным, графит вообще без цвета.
class PaletteTarget {
  /// Вещь, по которой назван цвет. Держит расчёт честным: если правка уводит
  /// цвет от предмета, это видно по имени, а не по числам.
  final String thing;
  final double hue;
  final double tone;
  final double k;

  const PaletteTarget(this.thing, this.hue, this.tone, this.k);
}

/// Одна палитра: имя, акцент, платность. Индекс сохраняем прежним — на нём
/// висит владение (`owned_themes` на сервере), ломать нельзя.
class Palette {
  final int index;
  final String name;

  /// Сид для ПОВЕРХНОСТЕЙ: фон, карточки, разделители по-прежнему считает M3.
  /// Акцент из него больше не выводится — его задаёт [target].
  final Color accent;
  final bool isPremium;
  final int price;

  /// Каким должен получиться акцент. См. [PaletteTarget].
  final PaletteTarget target;

  /// Как разворачивать акцент в схему. По умолчанию `tonalSpot` — спокойный
  /// вариант, который не задирает насыщенность (`vibrant` делал зелёные и
  /// бирюзовые темы кислотными). Отдельным палитрам нужен свой: «Монохром»
  /// из холодно-серого сида получал голубую схему, серым его делает `neutral`.
  final DynamicSchemeVariant variant;

  const Palette(this.index, this.name, this.accent,
      {this.isPremium = false,
      this.price = 0,
      this.variant = DynamicSchemeVariant.tonalSpot,
      required this.target});
}

/// Предельная насыщенность, которую sRGB даёт на этой паре «оттенок и тон».
double _maxChroma(double hue, double tone) => Hct.from(hue, 200, tone).chroma;

/// Заливка темы: пилюли, лепестки, круглые кнопки, активная навигация —
/// всё, поверх чего лежит текст. Цвет держит палитру, а надпись поверх берётся
/// через [AppThemes.onColor].
Color paletteFill(Palette p, Brightness brightness) {
  final t = p.target;
  // В тёмном режиме тот же цвет поднимается по тону: на чёрном фоне тёмная
  // заливка тонет, а сочность держится насыщенностью, не светлотой.
  final raw = brightness == Brightness.light
      ? t.tone
      : math.min(t.tone + 12, 88.0);
  return Color(
      Hct.from(t.hue, _maxChroma(t.hue, _readableTone(raw)) * t.k,
              _readableTone(raw))
          .toInt());
}

/// Мёртвая зона светлоты, где надпись поверх не читается НИКАКАЯ.
///
/// Белому нужен фон темнее 0.183 по яркости, тёмному — светлее 0.226; между
/// ними обе надписи дают меньше 4.5 по WCAG. В тонах HCT это узкая полоса
/// 49–56, и заливка из неё выталкивается к ближайшему краю. Разница в три-четыре
/// тона глазом не ловится, а «Монохром», «Нордик» и «Тёмный лес» переставали
/// быть читаемыми ровно в ней.
double _readableTone(double tone) {
  const lo = 49.0, hi = 56.0;
  if (tone <= lo || tone >= hi) return tone;
  return (tone - lo) < (hi - tone) ? lo : hi;
}

/// Акцент для надписей и мелких значков НА ФОНЕ экрана: тот же оттенок, но тон
/// подобран под контраст. Одним цветом заливку и надпись не покрасить — на
/// светлом фоне надпись обязана быть тёмной, а персик обязан быть светлым.
Color paletteInk(Palette p, Brightness brightness) {
  final t = p.target;
  final light = brightness == Brightness.light;
  final tone = light ? 36.0 : 86.0;
  final chroma = math.min(_maxChroma(t.hue, tone) * t.k, 55.0);
  return Color(Hct.from(t.hue, chroma, tone).toInt());
}

/// 25 палитр. Акценты разведены по оттенку и светлоте (мин. ΔE ≈ 17.7), чтобы
/// каждая была различима и совпадала с названием. Бесплатны первые пять.
const List<Palette> kPalettes = [
  Palette(0, 'Розовая', Color(0xFFFF7E9B), target: PaletteTarget('лепесток шиповника', 5, 64, 0.86)),
  Palette(1, 'Фиолетовая', Color(0xFF6E4FC0), target: PaletteTarget('спелая слива', 300, 44, 0.92)),
  Palette(2, 'Голубая', Color(0xFF56AEE8), target: PaletteTarget('июльское небо', 240, 66, 0.88)),
  Palette(3, 'Персиковая', Color(0xFFE8895A), target: PaletteTarget('мякоть персика', 30, 73, 1.0)),
  Palette(4, 'Шалфейная', Color(0xFF8CAE7E), target: PaletteTarget('лист шалфея', 140, 66, 0.48)),
  Palette(5, 'Полуночная', Color(0xFF33406E), isPremium: true, price: 30, target: PaletteTarget('небо за полночь', 270, 30, 0.78)),
  Palette(6, 'Лавандовая', Color(0xFFCBA6E6), isPremium: true, price: 30, target: PaletteTarget('поле лаванды', 310, 70, 0.66)),
  Palette(7, 'Вишнёвая', Color(0xFFB03A63), isPremium: true, price: 30, target: PaletteTarget('спелая вишня', 0, 45, 0.95)),
  Palette(8, 'Мятная', Color(0xFF74D8BE), isPremium: true, price: 30, target: PaletteTarget('мятный лист', 170, 76, 0.82)),
  Palette(9, 'Закатная', Color(0xFFFF6A47), isPremium: true, price: 30, target: PaletteTarget('закат над морем', 45, 60, 1.0)),
  Palette(10, 'Монохром', Color(0xFF6E7178),
      isPremium: true, price: 30, variant: DynamicSchemeVariant.neutral, target: PaletteTarget('графит', 258, 52, 0.08)),
  Palette(11, 'Лесная', Color(0xFF276E3C), isPremium: true, price: 30, target: PaletteTarget('еловая хвоя', 150, 44, 0.9)),
  Palette(12, 'Океан', Color(0xFF1685A2), isPremium: true, price: 30, target: PaletteTarget('океан на глубине', 220, 54, 0.92)),
  Palette(13, 'Медовая', Color(0xFFF0A81C), isPremium: true, price: 30, target: PaletteTarget('гречишный мёд', 75, 74, 0.98)),
  Palette(14, 'Лимонная', Color(0xFF9FCB2E), isPremium: true, price: 30, target: PaletteTarget('лимонная цедра', 110, 82, 0.94)),
  Palette(15, 'Песочная', Color(0xFFCDBE96), isPremium: true, price: 30, target: PaletteTarget('песок у воды', 80, 82, 0.34)),
  Palette(16, 'Северное сияние', Color(0xFF7C5CFF), isPremium: true, price: 40, target: PaletteTarget('северное сияние', 285, 54, 0.98)),
  Palette(17, 'Бордовая', Color(0xFF7C2E38), isPremium: true, price: 30, target: PaletteTarget('бордо в бокале', 10, 32, 0.88)),
  Palette(18, 'Бирюзовая', Color(0xFF16C2CE), isPremium: true, price: 30, target: PaletteTarget('бирюза', 195, 70, 0.96)),
  Palette(19, 'Нордик', Color(0xFF40699E), isPremium: true, price: 30, target: PaletteTarget('фьорд', 250, 50, 0.66)),
  Palette(20, 'Угольная бирюза', Color(0xFF1E7E70), isPremium: true, price: 30, target: PaletteTarget('малахит', 185, 46, 0.88)),
  Palette(21, 'Кофе', Color(0xFF9C6E45), isPremium: true, price: 30, target: PaletteTarget('обжаренное зерно', 50, 44, 0.44)),
  Palette(22, 'Тёмный лес', Color(0xFF2FA355), isPremium: true, price: 30, target: PaletteTarget('чаща', 155, 40, 0.92)),
  Palette(23, 'Гранат', Color(0xFFE05A62), isPremium: true, price: 30, target: PaletteTarget('зерно граната', 15, 48, 0.92)),
  Palette(24, 'Тёмный мёд', Color(0xFFC8912E), isPremium: true, price: 30, target: PaletteTarget('тёмный мёд', 68, 60, 0.92)),
];

Palette paletteByIndex(int index) =>
    (index >= 0 && index < kPalettes.length) ? kPalettes[index] : kPalettes[0];

// ── Цветовая математика (совпадает с утверждённым макетом) ──
Color _lighten(Color c, double f) => Color.lerp(c, Colors.white, f)!;
Color _darken(Color c, double f) => Color.lerp(c, Colors.black, f)!;

/// Собирает [AppTheme] из палитры и режима. Все поверхности/текст — из M3-схемы
/// (tonalSpot/vibrant/fidelity), а идентичность (primary, hero) — из самого
/// акцента. В тёмном режиме тёмные акценты подсвечиваются, чтобы не тонуть.
/// Насыщенность акцента под выбранную «сочность».
///
/// Крутится ТОЛЬКО хрома: оттенок и светлота остаются, поэтому вишня остаётся
/// вишней, а не уезжает в малину. Почти нейтральное (хрома ниже шести) не
/// трогаем вовсе — иначе «Монохром» на «сочно» перестал бы быть серым.
Color _juice(Color c, SchemeFlavor f) {
  if (f == SchemeFlavor.soft) return c;
  final h = Hct.fromInt(c.toARGB32());
  if (h.chroma < 6) return c;

  // Одной хромы мало. Пастельный акцент вроде розового `#FF7E8B` уже стоит на
  // пределе, достижимом в sRGB для своей светлоты, и множитель на нём не
  // делает ничего — переключатель снова выглядел бы мёртвым. Густота цвета
  // берётся тоном: чем ниже тон, тем выше достижимая насыщенность. Поэтому
  // «сочно» и «точь-в-точь» сначала опускают светлоту, а уже на новом тоне
  // выбирают предел.
  final drop = f == SchemeFlavor.juicy ? 7.0 : 14.0;
  // В тёмной теме опускать некуда: акцент там светлый именно для того, чтобы
  // читаться на чёрном, и уводить его вниз значит топить надпись.
  // Тон только опускаем и только до тридцати: ниже цвет перестаёт быть собой
  // и становится почти чёрным. Порога «не ниже исходного» тут нет намеренно —
  // у тёмных акцентов вроде угольной бирюзы насыщенность уже на пределе sRGB,
  // и единственная оставшаяся густота берётся светлотой.
  final tone = math.max(h.tone - drop, 30.0);
  final limit = _maxChroma(h.hue, tone);
  final chroma = f == SchemeFlavor.juicy
      ? math.min(h.chroma * 1.35, limit)
      : limit; // «точь-в-точь» — предел, достижимый в sRGB на этом оттенке
  return Color(Hct.from(h.hue, chroma, tone).toInt());
}

/// Ручная тема с подкрученным акцентом.
///
/// Фон, карточки, текст и разделители не трогаем: «сочность» про цвет темы, а
/// не про то, чтобы залить страницу. Меняются ровно те поля, которыми красятся
/// цветные места — заливки, значки, круг, активная навигация.
AppTheme _juiced(AppTheme t, SchemeFlavor f, Palette p) {
  Color j(Color c) => _juice(c, f);
  final accent = j(t.primary);
  // Схема нужна даже когда цвета не меняются. `ProfileTheme` строит её из
  // `AppTheme.primary`, а `fromSeed` отдаёт по сиду ПРОИЗВОДНЫЙ тон — из-за
  // этого лист «Хочу с тобой» красился бледнее главной. Кладём схему рядом с
  // темой и подменяем в ней акцентные роли своими цветами.
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: t.brightness,
    dynamicSchemeVariant: p.variant,
  ).copyWith(
    primary: accent,
    onPrimary: AppThemes.onColor(accent, mode: t.brightness),
    // Контейнер — светлая тональная подложка, а НЕ тот же акцент. Пока они
    // совпадали, значок цветом `primary` на подложке `primaryContainer`
    // становился цветом по цвету: в выборе типа связи иконок не было видно
    // вовсе.
    primaryContainer: j(t.primaryLight),
    onPrimaryContainer: accent,
  );
  return AppTheme(
    index: t.index,
    name: t.name,
    primary: accent,
    accentFill: t.accentFill == null ? null : j(t.accentFill!),
    primaryLight: j(t.primaryLight),
    bgGradient: t.bgGradient,
    bgImageUrl: t.bgImageUrl,
    heroGradient: t.heroGradient.map(j).toList(),
    heroGlassOpacity: t.heroGlassOpacity,
    heroToggleBorder: t.heroToggleBorder,
    heroToggleSelectedColor: j(t.heroToggleSelectedColor),
    cardSurface: t.cardSurface,
    cardBorder: t.cardBorder,
    iconDraw: j(t.iconDraw),
    iconMood: j(t.iconMood),
    iconCalendar: j(t.iconCalendar),
    iconPost: j(t.iconPost),
    navActiveBg: j(t.navActiveBg),
    navActiveIcon: j(t.navActiveIcon),
    promptButtonColor: j(t.promptButtonColor),
    timerDialBackground: j(t.timerDialBackground),
    isPremium: t.isPremium,
    price: t.price,
    brightness: t.brightness,
    scheme: scheme,
    textPrimary: t.textPrimary,
    textSecondary: t.textSecondary,
    textMuted: t.textMuted,
    surfaceMuted: t.surfaceMuted,
    divider: t.divider,
  );
}

AppTheme buildAppTheme(
  Palette p,
  Brightness brightness, {
  SchemeFlavor flavor = SchemeFlavor.soft,
  bool amoled = false,
}) {
  // Тема, нарисованная руками, выигрывает у вычисленной.
  //
  // Двадцать светлых и пять тёмных тем подобраны попарно: винная вишня на
  // бледно-розовом, белые карточки, пыльно-розовый трек круга. Вычисленная
  // схема этого не воспроизводит — она берёт из сида только оттенок, и
  // вишнёвая уезжала в кричащую маджентовую. Поэтому там, где ручная тема
  // есть в нужной яркости, отдаём её как есть; считаем только сочетания,
  // которых до появления тёмного режима не существовало (тёмные версии
  // двадцати светлых палитр и светлые версии пяти тёмных).
  final legacy = AppThemes.byIndex(p.index);
  if (legacy.brightness == brightness && !amoled) {
    return _juiced(legacy, flavor, p);
  }

  // Сид считаем от акцента ручной темы, а не от цели палитры: так тёмная
  // вишнёвая остаётся роднёй светлой вишнёвой, а не отдельным цветом.
  final src = Hct.fromInt(legacy.primary.toARGB32());
  final s = ColorScheme.fromSeed(
    seedColor: legacy.primary,
    brightness: brightness,
    // «Мягкий» вариант палитра вправе уточнить: «Монохром» из холодно-серого
    // сида получал у tonalSpot голубую схему и серым не выглядел.
    dynamicSchemeVariant:
        flavor == SchemeFlavor.soft ? p.variant : flavor.variant,
  );
  final dark = brightness == Brightness.dark;

  // Акцентов ДВА. Заливка держит цвет темы (`fill`), а надпись и мелкие
  // значки на фоне — контраст (`ink`). Оттенок у них общий, так что тема
  // остаётся собой. В тёмной заливка поднимается по тону: на чёрном фоне
  // винный тон тонет, и цвет держится светлотой, а не насыщенностью.
  final fillTone = dark ? math.min(math.max(src.tone + 24, 58.0), 80.0) : src.tone;
  final fill = _juice(
      Color(Hct.from(src.hue, src.chroma, fillTone).toInt()), flavor);
  final acc = _juice(
      Color(Hct.from(src.hue, math.min(src.chroma, 55), dark ? 86.0 : 36.0)
          .toInt()),
      flavor);

  final card = (dark && amoled) ? const Color(0xFF181818) : s.surfaceContainerHigh;
  final bg1 = (dark && amoled) ? const Color(0xFF000000) : s.surface;
  final bg2 =
      (dark && amoled) ? const Color(0xFF000000) : s.surfaceContainerLow;
  final muted =
      (dark && amoled) ? const Color(0xFF222222) : s.surfaceContainerHighest;

  return AppTheme(
    index: p.index,
    name: p.name,
    isPremium: p.isPremium,
    price: p.price,
    brightness: brightness,
    // Схема едет вместе с темой: экраны на M3 берут её как есть, а не собирают
    // заново из `primary` — тот уже производный, и повторный сид терял вариант.
    // Акценты в ней подменены на наши: `primary` — надпись (контраст),
    // `primaryContainer` — заливка (цвет темы). Так сочность доезжает до всех
    // экранов на ролях M3 без обхода полутысячи мест руками.
    scheme: s.copyWith(
      primary: acc,
      onPrimary: AppThemes.onColor(acc, mode: brightness),
      primaryContainer: fill,
      onPrimaryContainer: AppThemes.onColor(fill, mode: brightness),
    ),
    primary: acc,
    accentFill: fill,
    primaryLight: Color.alphaBlend(
      fill.withValues(alpha: dark ? 0.30 : 0.42),
      s.surfaceContainerHigh,
    ),
    bgGradient: [bg1, bg2],
    // Hero — крупная заливка, ей нужен цвет темы, а не тон надписи.
    heroGradient: [_lighten(fill, 0.04), _darken(fill, 0.18)],
    heroGlassOpacity: 0.20,
    heroToggleBorder: !dark,
    heroToggleSelectedColor: acc,
    cardSurface: card,
    cardBorder: s.outlineVariant,
    iconDraw: acc,
    iconMood: acc,
    iconCalendar: acc,
    iconPost: acc,
    // Подложка активного пункта — заливка, значок поверх неё считает onColor.
    navActiveBg: fill,
    navActiveIcon: AppThemes.onColor(fill, mode: brightness),
    // Кнопка подсказки — заливка с текстом поверх.
    promptButtonColor: fill,
    // Лепестки занимают половину экрана, поэтому чистый `primaryContainer`
    // давал грязное пятно: охру у Медовой, хаки у Лимонной, ржавчину у
    // Персиковой. Приглушение тональной поверхностью спасло светлые темы, а
    // тёмные — нет: на чёрном фоне светлый акцент, размешанный на четверть,
    // даёт мутный `#64484E`, и это второй по площади цвет всего экрана.
    // В тёмной теме трек берём чистой поверхностью: круг становится спокойным
    // кольцом, на котором заполненный сектор читается цветом темы.
    timerDialBackground: dark
        ? s.surfaceContainerHigh
        : Color.alphaBlend(
            fill.withValues(alpha: 0.34),
            s.surfaceContainerHigh,
          ),
    textPrimary: s.onSurface,
    textSecondary: s.onSurfaceVariant,
    textMuted: s.outline,
    surfaceMuted: muted,
    divider: s.outlineVariant,
  );
}
