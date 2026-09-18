import 'package:flutter/material.dart';
import '../../widgets/mood_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/animations.dart';

/// Ряд быстрых кнопок под таймером: рисование, настроение, календарь, фото и
/// по центру, на дне дуги, Togetherly Wallet.
///
/// Кнопка Wallet окрашена наоборот: заливка темы, значок белый (на тёмных темах
/// заливка светлая, и значок берёт тёмный цвет — считает [AppThemes.onColor]).
/// Пока Wallet не вышел, она открывает стену ожидания, после выхода — сам
/// Wallet; решает `WalletTeaser`, а не ряд. Без [onWallet] ряд остаётся из
/// четырёх, как раньше.
///
/// Показывается только в паре — все четыре пишут в коллекции с `group_id`, и
/// без партнёра ни одна не работает. Раньше ряд висел выключенным: белые пилюли
/// под общей прозрачностью выглядели выцветшими, а рисование к тому же
/// оставалось активным и молча теряло нарисованное (`createStroke` выходит на
/// пустом groupId). Теперь без пары на этом месте стоит приглашение.
class HomeActionButtons extends StatelessWidget {
  final AppTheme theme;
  final bool isPaired;
  final String myMoodImagePath;
  final VoidCallback onDraw;
  final VoidCallback onMood;
  final VoidCallback onCalendar;
  final VoidCallback onPost;

  /// Удержание кнопки фото: снимается ролик на пару секунд и уходит живым
  /// фото в парный виджет. Тап остаётся обычным снимком.
  final VoidCallback? onPostHold;

  /// Ключ кнопки фото — за него держится подсказка про удержание.
  final GlobalKey? postButtonKey;

  /// Кнопка Togetherly Wallet в середине ряда. null — ряд из четырёх.
  final VoidCallback? onWallet;

  const HomeActionButtons({
    super.key,
    required this.theme,
    required this.isPaired,
    required this.myMoodImagePath,
    required this.onDraw,
    required this.onMood,
    required this.onCalendar,
    required this.onPost,
    this.onPostHold,
    this.postButtonKey,
    this.onWallet,
  });

  static const String _drawSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M21.731 2.269a2.625 2.625 0 0 0-3.712 0l-1.157 1.157 3.712 3.712 1.157-1.157a2.625 2.625 0 0 0 0-3.712ZM19.513 8.199l-3.712-3.712-8.4 8.4a5.25 5.25 0 0 0-1.32 2.214l-.8 2.685a.75.75 0 0 0 .933.933l2.685-.8a5.25 5.25 0 0 0 2.214-1.32l8.4-8.4Z" />\n  <path d="M5.25 5.25a3 3 0 0 0-3 3v10.5a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3V13.5a.75.75 0 0 0-1.5 0v5.25a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5V8.25a1.5 1.5 0 0 1 1.5-1.5h5.25a.75.75 0 0 0 0-1.5H5.25Z" />\n</svg>';

  static const String _moodSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-2.625 6c-.54 0-.828.419-.936.634a1.96 1.96 0 0 0-.189.866c0 .298.059.605.189.866.108.215.395.634.936.634.54 0 .828-.419.936-.634.13-.26.189-.568.189-.866 0-.298-.059-.605-.189-.866-.108-.215-.395-.634-.936-.634Zm4.314.634c.108-.215.395-.634.936-.634.54 0 .828.419.936.634.13.26.189.568.189.866 0 .298-.059.605-.189.866-.108.215-.395.634-.936.634-.54 0-.828-.419-.936-.634a1.96 1.96 0 0 1-.189-.866c0-.298.059-.605.189-.866Zm2.023 6.828a.75.75 0 1 0-1.06-1.06 3.75 3.75 0 0 1-5.304 0 .75.75 0 0 0-1.06 1.06 5.25 5.25 0 0 0 7.424 0Z" clip-rule="evenodd" />\n</svg>';

  static const String _calendarSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12.75 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM7.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM8.25 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM9.75 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM10.5 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM12 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM12.75 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM14.25 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" />\n  <path fill-rule="evenodd" d="M6.75 2.25A.75.75 0 0 1 7.5 3v1.5h9V3A.75.75 0 0 1 18 3v1.5h.75a3 3 0 0 1 3 3v11.25a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3V7.5a3 3 0 0 1 3-3H6V3a.75.75 0 0 1 .75-.75Zm13.5 9a1.5 1.5 0 0 0-1.5-1.5H5.25a1.5 1.5 0 0 0-1.5 1.5v7.5a1.5 1.5 0 0 0 1.5 1.5h13.5a1.5 1.5 0 0 0 1.5-1.5v-7.5Z" clip-rule="evenodd" />\n</svg>';

  /// Купюры (Heroicons solid, как и остальные значки ряда).
  static const String _walletSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor">\n  <path d="M12 7.5a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Z" />\n  <path fill-rule="evenodd" d="M1.5 4.875C1.5 3.839 2.34 3 3.375 3h17.25c1.035 0 1.875.84 1.875 1.875v9.75c0 1.036-.84 1.875-1.875 1.875H3.375A1.875 1.875 0 0 1 1.5 14.625v-9.75ZM8.25 9.75a3.75 3.75 0 1 1 7.5 0 3.75 3.75 0 0 1-7.5 0ZM18.75 9a.75.75 0 0 0-.75.75v.008c0 .414.336.75.75.75h.008a.75.75 0 0 0 .75-.75V9.75a.75.75 0 0 0-.75-.75h-.008ZM4.5 9.75A.75.75 0 0 1 5.25 9h.008a.75.75 0 0 1 .75.75v.008a.75.75 0 0 1-.75.75H5.25a.75.75 0 0 1-.75-.75V9.75Z" clip-rule="evenodd" />\n  <path d="M2.25 18a.75.75 0 0 0 0 1.5c5.4 0 10.63.722 15.6 2.075 1.19.324 2.4-.558 2.4-1.82V18.75a.75.75 0 0 0-.75-.75H2.25Z" />\n</svg>';

  static const String _postSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12 9a3.75 3.75 0 1 0 0 7.5A3.75 3.75 0 0 0 12 9Z" />\n  <path fill-rule="evenodd" d="M9.344 3.071a49.52 49.52 0 0 1 5.312 0c.967.052 1.83.585 2.332 1.39l.821 1.317c.24.383.645.643 1.11.71.386.054.77.113 1.152.177 1.432.239 2.429 1.493 2.429 2.909V18a3 3 0 0 1-3 3h-15a3 3 0 0 1-3-3V9.574c0-1.416.997-2.67 2.429-2.909.382-.064.766-.123 1.151-.178a1.56 1.56 0 0 0 1.11-.71l.822-1.315a2.942 2.942 0 0 1 2.332-1.39ZM6.75 12.75a5.25 5.25 0 1 1 10.5 0 5.25 5.25 0 0 1-10.5 0Zm12-1.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clip-rule="evenodd" />\n</svg>';

  /// Насколько две средние кнопки уезжают вниз ради параболического изгиба.
  static const double _bend = 11.0;

  /// Дуга ряда из пяти: крайние на месте, соседние центра ниже, центр ниже
  /// всех — парабола 0 / ¾ / 1 от этой глубины.
  static const double _bend5 = 14.0;

  /// В ряду из пяти зазор уже, а пилюля может сжаться до 44: на 320 dp пять
  /// пилюль по 56 с зазорами в десять не помещаются вовсе (5×56 + 40 = 320 при
  /// ширине ряда 272). Цель под палец и так не уже сорока точек.
  static const double _gap5 = 8.0;
  static const double _pill5MinWidth = 44.0;

  /// Зазор между пилюлями и границы их ширины. Меньше 56 нельзя: цель под
  /// палец по правилу проекта не бывает уже сорока точек, а внутри пилюли
  /// ещё живёт значок.
  static const double _gap = 10.0;
  static const double _pillMinWidth = 56.0;
  static const double _pillMaxWidth = 74.0;

  /// Пилюля выше своей ширины — пропорция прежняя, 74 на 118.
  static const double _pillRatio = 118 / 74;

  @override
  Widget build(BuildContext context) {
    // Изгиб делается `Transform.translate`, а он двигает картинку, не занимая
    // места: ряд отдавал раскладке высоту без учёта смещения, и следующий блок
    // (карточка маскота) подлезал средним кнопкам под низ. Добираем отступ
    // ровно на величину изгиба.
    if (onWallet != null) return _fiveRow(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: _bend),
      // Ширина пилюли считается от экрана, а не задана числом: четыре по 74
      // с зазорами это 326 точек, и на 320 ряд вылезал вправо на 54 пикселя
      // (эмулятор, `wm size 720x1600` + `wm density 360`, шрифт 1.3).
      child: LayoutBuilder(builder: (context, box) {
        final free = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.of(context).size.width;
        final width =
            ((free - _gap * 3) / 4).clamp(_pillMinWidth, _pillMaxWidth);
        final height = width * _pillRatio;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pillButton(
              index: 0,
              svgIcon: _drawSvg,
              enabled: isPaired,
              onTap: onDraw,
              width: width,
              height: height,
            ),
            const SizedBox(width: _gap),
            _pillButton(
              index: 1,
              svgIcon: _moodSvg,
              enabled: isPaired,
              onTap: onMood,
              moodImagePath: myMoodImagePath,
              width: width,
              height: height,
            ),
            const SizedBox(width: _gap),
            _pillButton(
              index: 2,
              svgIcon: _calendarSvg,
              enabled: isPaired,
              onTap: onCalendar,
              width: width,
              height: height,
            ),
            const SizedBox(width: _gap),
            _pillButton(
              index: 3,
              svgIcon: _postSvg,
              enabled: isPaired,
              onTap: onPost,
              onLongPress: onPostHold,
              key: postButtonKey,
              width: width,
              height: height,
            ),
          ],
        );
      }),
    );
  }

  Widget _fiveRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _bend5),
      child: LayoutBuilder(builder: (context, box) {
        final free = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.of(context).size.width;
        final width =
            ((free - _gap5 * 4) / 5).clamp(_pill5MinWidth, _pillMaxWidth);
        final height = width * _pillRatio;
        double dip(int i) {
          final k = (i - 2) / 2;
          return _bend5 * (1 - k * k);
        }

        final fill = theme.fillColor;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pillButton(
              index: 0,
              svgIcon: _drawSvg,
              onTap: onDraw,
              width: width,
              height: height,
              dy: dip(0),
            ),
            const SizedBox(width: _gap5),
            _pillButton(
              index: 1,
              svgIcon: _moodSvg,
              onTap: onMood,
              moodImagePath: myMoodImagePath,
              width: width,
              height: height,
              dy: dip(1),
            ),
            const SizedBox(width: _gap5),
            Semantics(
              button: true,
              label: 'Togetherly Wallet',
              child: _pillButton(
                index: 2,
                svgIcon: _walletSvg,
                onTap: onWallet,
                width: width,
                height: height,
                dy: dip(2),
                fill: fill,
                iconColor: AppThemes.onColor(fill, mode: theme.brightness),
              ),
            ),
            const SizedBox(width: _gap5),
            _pillButton(
              index: 3,
              svgIcon: _calendarSvg,
              onTap: onCalendar,
              width: width,
              height: height,
              dy: dip(3),
            ),
            const SizedBox(width: _gap5),
            _pillButton(
              index: 4,
              svgIcon: _postSvg,
              onTap: onPost,
              onLongPress: onPostHold,
              key: postButtonKey,
              width: width,
              height: height,
              dy: dip(4),
            ),
          ],
        );
      }),
    );
  }

  Widget _pillButton({
    required int index,
    required String svgIcon,
    required double width,
    required double height,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? moodImagePath,
    Key? key,
    double? dy,
    Color? fill,
    Color? iconColor,
  }) {
    final opacity = enabled ? 1.0 : 0.4;
    final hasMoodImage = moodImagePath != null && moodImagePath.isNotEmpty;

    // Смещение вниз для кнопок 1 и 2 (параболический изгиб). Ряд из пяти
    // передаёт свою дугу сам.
    final double shift = dy ?? ((index == 1 || index == 2) ? _bend : 0.0);

    return Transform.translate(
      key: key,
      offset: Offset(0, shift),
      child: Opacity(
        opacity: opacity,
        child: QuickTapScale(
          onTap: enabled ? (onTap ?? () {}) : null,
          onLongPress: enabled ? onLongPress : null,
          scale: 0.92,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              // Светлая тема — чистый белый: тональный surfaceContainerHigh
              // (его отдаёт cardSurface) выглядел на бледном фоне грязно-серым.
              // Тёмная остаётся на поверхности карточки, там белый бы слепил.
              color: fill ?? (theme.isDark ? theme.cardSurface : Colors.white),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: hasMoodImage
                    ? ClipOval(
                        child: MoodImage(
                          moodImagePath,
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                        ),
                      )
                    : _svgIcon(svgIcon, 30, iconColor ?? theme.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _svgIcon(String svg, double size, Color color) {
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
