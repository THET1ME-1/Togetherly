# Дни вместе — «Кольцо года» и «Календарь лет» (Flutter)

Два виджета домашнего экрана для приложения для пар. Каждый в двух размерах: **4×2** и **2×2**.
Источник истины по внешнему виду — `days-widget-reference.html` (открыть в браузере,
все стили инлайн = спецификация).

Стек: Flutter. Виджеты домашнего экрана рисуются **нативно** (Flutter не рендерит home-screen widgets):
Android — Glance/RemoteViews, iOS — WidgetKit/SwiftUI. Данные передаются из Flutter через
`home_widget` (SharedPreferences / App Group). Значения ниже — уже готовые константы.

## Токены (Dart)

```dart
// lib/theme/couple_tokens.dart
abstract class T {
  // brand
  static const coral       = Color(0xFFF2607A); // акцент, прогресс
  static const coralDeep   = Color(0xFFE03B5E); // подписи-акценты
  static const coralPress  = Color(0xFFC82748); // конец градиента кнопки
  static const pink        = Color(0xFFFF8FA8); // подпись на тёмном
  static const pinkPale    = Color(0xFFFFD9E1); // пустые точки
  // ink & surface
  static const ink         = Color(0xFF241C29); // текст, тёмный фон виджета
  static const inkLift     = Color(0xFF3B2F3E); // блоки на тёмном фоне
  static const muted       = Color(0xFF9A8E97); // вторичный текст
  static const cream       = Color(0xFFFFF6F1); // светлый фон виджета
  static const white       = Color(0xFFFFFFFF);
  static const hairline    = Color(0x24F2607A); // rgba(240,96,122,.14) — внутр. обводка
}
```

Шрифт: **Manrope**, веса 700/800 (в макете использованы только они).
Тексты-числа — w800 с отрицательным трекингом (значения ниже даны для каждого места).
Скругления виджета: **34**; внутренние блоки: 20 / 18 / 16; pill: 999.

---

## Вариант A — «Кольцо года» (`YearRingWidget`)

Тёмный виджет: круговой прогресс до следующей годовщины, число дней в центре.

### 4×2 (472 × 224 логических px)
- Фон `T.ink`, radius 34, padding: 22 сверху/снизу, 26 по бокам. Row, gap **28**, `crossAxisAlignment: center`.
- **Кольцо** 150×150, не сжимается:
  - трек: круг r=42 (в системе координат 100×100), stroke `T.inkLift`, ширина 9;
  - прогресс: тот же радиус, stroke `T.coral`, ширина 9, `StrokeCap.round`,
    старт **−90°** (12 часов), по часовой; заполнение = `daysIntoYear / 365`
    (в макете dasharray 264 / dashoffset 245 → **7.2 %**, т.е. 10 дней из 365).
  - в центре Column: `2126` — 34px w800, трекинг −1.4, white; под ним `дней` — 12px w800, `T.pink`.
- **Правая колонка** (Expanded), Column gap 12:
  - `ШЕСТОЙ ГОД ВМЕСТЕ` — 12.5px w800, трекинг +0.3, `T.muted`, uppercase;
  - `Ещё 355 дней` — 24px w800, трекинг −0.7, white;
  - `до 6 лет · 30.09.2026` — 13.5px w800, `T.pink`;
  - Row gap 8 из двух плиток (`Expanded` каждая): фон `T.inkLift`, radius 16,
    padding 11 верт / 13 гориз; внутри `МЕСЯЦЕВ` / `ВСТРЕЧ` 11.5px w800 `T.muted`
    и значение `69` / `412` 20px w800 трекинг −0.5 white.

### 2×2 (224 × 224)
- Фон `T.ink`, radius 34. Кольцо 176×176 по центру (stroke 8, те же цвета и прогресс).
- Поверх по центру Column: `2126` 44px w800 трекинг −2 white → `дней вместе` 13px w800 `T.pink`
  → отступ 4 → `до 6 лет — 355` 11.5px w800 `T.muted`.

### Данные
`daysTotal`, `yearsCompleted`, `daysIntoYear`, `daysToNextAnniversary`,
`nextAnniversaryDate`, `monthsTotal`, `meetingsCount`.

---

## Вариант B — «Календарь лет» (`YearGridWidget`)

Светлый виджет: сетка точек, **точка = месяц, ряд = год**.

Сетка всегда **6 рядов × 12 точек = 72 месяца (6 лет)**. Правило заливки:
```
i < monthsCompleted        -> T.coral      (прожитый месяц)
i == monthsCompleted       -> T.coralDeep  (текущий месяц)
i > monthsCompleted        -> T.pinkPale   (впереди)
```
В макете `monthsCompleted = 68`. Когда 6 лет пройдут — сетка расширяется на следующие 6 лет
(72 → 144 месяца, рядов становится 12; при этом уменьшать размер точки, не менять число колонок).

### 4×2 (472 × 224)
- Фон `T.cream`, radius 34, padding 22 верт / 26 гориз, внутренняя обводка 1px `T.hairline`.
  Column, `MainAxisAlignment.spaceBetween`.
- **Верхняя строка** (Row, `CrossAxisAlignment.end`, `spaceBetween`):
  - слева Row `end`, gap 8: `2126` 60px w800 трекинг −2.8 `T.ink`;
    `дней` 17px w800 `T.muted` с отступом снизу 8;
  - справа Column `end`: `5 ЛЕТ 10 ДНЕЙ` 12.5px w800 `T.coralDeep`;
    `с 30.09.2020` 12.5px w800 `T.muted`.
- **Низ** (Row `end`, gap 14):
  - сетка: 6 рядов, точка **9×9**, gap **5** и по X и по Y, круглая;
  - справа плитка (не растягивается): фон white, radius 20, padding 11 верт / 15 гориз,
    Column center gap 3: `355` 22px w800 трекинг −0.8 `T.coralDeep`, `до 6 лет` 11px w800 `T.muted`.

### 2×2 (224 × 224)
- Фон `T.cream`, radius 34, padding 20, внутренняя обводка `T.hairline`.
  Column `spaceBetween`.
- Сверху та же сетка: 6 рядов, точка **8×8**, gap **4**.
- Снизу Column gap 1: `2126` 52px w800 трекинг −2.3 `T.ink`;
  `дней вместе` 14.5px w800 `T.coralDeep`; отступ 3; `6-й год · ещё 355` 12px w800 `T.muted`.

### Данные
`daysTotal`, `monthsCompleted`, `yearsCompleted`, `startDate`, `daysToNextAnniversary`.

---

## Общее поведение
- Пересчёт раз в сутки в полночь по локальному времени (Android: `WorkManager` daily;
  iOS: `WidgetKit` timeline с точкой на 00:00).
- Тап по виджету открывает экран «Наша история» (deep link `togetherly://history`).
- Пустое состояние (партнёр не подключён / дата не задана): тот же фон и радиус,
  по центру `Укажите дату начала` 15px w800 `T.muted`, кнопки нет.
- Локаль: русский, склонение «день/дня/дней» по числу (`Intl.plural`).
- Тёмная тема системы: «Кольцо года» уже тёмное — не меняется;
  «Календарь лет» в dark mode: фон `T.ink`, `T.ink`-текст → white, `T.muted` остаётся,
  плитка `white` → `T.inkLift`, пустые точки `T.pinkPale` → `T.inkLift`.

## Файлы
- `days-widget-reference.html` — точный визуальный референс, оба варианта в двух размерах.
- `PROMPT.md` — текст для Claude Code.
