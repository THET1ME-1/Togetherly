import 'package:flutter/material.dart';
import '../../widgets/mood_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/animations.dart';

/// Ряд из 4 быстрых кнопок под таймером: рисование, настроение, календарь, фото.
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
  });

  static const String _drawSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M21.731 2.269a2.625 2.625 0 0 0-3.712 0l-1.157 1.157 3.712 3.712 1.157-1.157a2.625 2.625 0 0 0 0-3.712ZM19.513 8.199l-3.712-3.712-8.4 8.4a5.25 5.25 0 0 0-1.32 2.214l-.8 2.685a.75.75 0 0 0 .933.933l2.685-.8a5.25 5.25 0 0 0 2.214-1.32l8.4-8.4Z" />\n  <path d="M5.25 5.25a3 3 0 0 0-3 3v10.5a3 3 0 0 0 3 3h10.5a3 3 0 0 0 3-3V13.5a.75.75 0 0 0-1.5 0v5.25a1.5 1.5 0 0 1-1.5 1.5H5.25a1.5 1.5 0 0 1-1.5-1.5V8.25a1.5 1.5 0 0 1 1.5-1.5h5.25a.75.75 0 0 0 0-1.5H5.25Z" />\n</svg>';

  static const String _moodSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-2.625 6c-.54 0-.828.419-.936.634a1.96 1.96 0 0 0-.189.866c0 .298.059.605.189.866.108.215.395.634.936.634.54 0 .828-.419.936-.634.13-.26.189-.568.189-.866 0-.298-.059-.605-.189-.866-.108-.215-.395-.634-.936-.634Zm4.314.634c.108-.215.395-.634.936-.634.54 0 .828.419.936.634.13.26.189.568.189.866 0 .298-.059.605-.189.866-.108.215-.395.634-.936.634-.54 0-.828-.419-.936-.634a1.96 1.96 0 0 1-.189-.866c0-.298.059-.605.189-.866Zm2.023 6.828a.75.75 0 1 0-1.06-1.06 3.75 3.75 0 0 1-5.304 0 .75.75 0 0 0-1.06 1.06 5.25 5.25 0 0 0 7.424 0Z" clip-rule="evenodd" />\n</svg>';

  static const String _calendarSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12.75 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM7.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM8.25 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM9.75 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM10.5 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM12 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM12.75 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM14.25 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 17.25a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 15.75a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5ZM15 12.75a.75.75 0 1 1-1.5 0 .75.75 0 0 1 1.5 0ZM16.5 13.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" />\n  <path fill-rule="evenodd" d="M6.75 2.25A.75.75 0 0 1 7.5 3v1.5h9V3A.75.75 0 0 1 18 3v1.5h.75a3 3 0 0 1 3 3v11.25a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3V7.5a3 3 0 0 1 3-3H6V3a.75.75 0 0 1 .75-.75Zm13.5 9a1.5 1.5 0 0 0-1.5-1.5H5.25a1.5 1.5 0 0 0-1.5 1.5v7.5a1.5 1.5 0 0 0 1.5 1.5h13.5a1.5 1.5 0 0 0 1.5-1.5v-7.5Z" clip-rule="evenodd" />\n</svg>';

  static const String _postSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="size-6">\n  <path d="M12 9a3.75 3.75 0 1 0 0 7.5A3.75 3.75 0 0 0 12 9Z" />\n  <path fill-rule="evenodd" d="M9.344 3.071a49.52 49.52 0 0 1 5.312 0c.967.052 1.83.585 2.332 1.39l.821 1.317c.24.383.645.643 1.11.71.386.054.77.113 1.152.177 1.432.239 2.429 1.493 2.429 2.909V18a3 3 0 0 1-3 3h-15a3 3 0 0 1-3-3V9.574c0-1.416.997-2.67 2.429-2.909.382-.064.766-.123 1.151-.178a1.56 1.56 0 0 0 1.11-.71l.822-1.315a2.942 2.942 0 0 1 2.332-1.39ZM6.75 12.75a5.25 5.25 0 1 1 10.5 0 5.25 5.25 0 0 1-10.5 0Zm12-1.5a.75.75 0 1 0 0-1.5.75.75 0 0 0 0 1.5Z" clip-rule="evenodd" />\n</svg>';

  /// Насколько две средние кнопки уезжают вниз ради параболического изгиба.
  static const double _bend = 11.0;

  @override
  Widget build(BuildContext context) {
    // Изгиб делается `Transform.translate`, а он двигает картинку, не занимая
    // места: ряд отдавал раскладке высоту без учёта смещения, и следующий блок
    // (карточка маскота) подлезал средним кнопкам под низ. Добираем отступ
    // ровно на величину изгиба.
    return Padding(
      padding: const EdgeInsets.only(bottom: _bend),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
        _pillButton(
          index: 0,
          svgIcon: _drawSvg,
          enabled: isPaired,
          onTap: onDraw,
        ),
        const SizedBox(width: 10),
        _pillButton(
          index: 1,
          svgIcon: _moodSvg,
          enabled: isPaired,
          onTap: onMood,
          moodImagePath: myMoodImagePath,
        ),
        const SizedBox(width: 10),
        _pillButton(
          index: 2,
          svgIcon: _calendarSvg,
          enabled: isPaired,
          onTap: onCalendar,
        ),
        const SizedBox(width: 10),
        _pillButton(
          index: 3,
          svgIcon: _postSvg,
          enabled: isPaired,
          onTap: onPost,
          onLongPress: onPostHold,
        ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required int index,
    required String svgIcon,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    String? moodImagePath,
  }) {
    final opacity = enabled ? 1.0 : 0.4;
    final hasMoodImage = moodImagePath != null && moodImagePath.isNotEmpty;

    // Смещение вниз для кнопок 1 и 2 (параболический изгиб)
    final double dy = (index == 1 || index == 2) ? _bend : 0.0;

    return Transform.translate(
      offset: Offset(0, dy),
      child: Opacity(
        opacity: opacity,
        child: QuickTapScale(
          onTap: enabled ? (onTap ?? () {}) : null,
          onLongPress: enabled ? onLongPress : null,
          scale: 0.92,
          child: Container(
            width: 74,
            height: 118,
            decoration: BoxDecoration(
              // Светлая тема — чистый белый: тональный surfaceContainerHigh
              // (его отдаёт cardSurface) выглядел на бледном фоне грязно-серым.
              // Тёмная остаётся на поверхности карточки, там белый бы слепил.
              color: theme.isDark ? theme.cardSurface : Colors.white,
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
                    : _svgIcon(svgIcon, 30, theme.primary),
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
