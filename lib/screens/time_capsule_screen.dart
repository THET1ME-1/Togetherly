import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/capsule_schedule.dart';
import '../models/memory.dart';
import '../utils/safe_pick.dart';
import '../services/capsule_notification_service.dart';
import '../services/locale_service.dart';
import '../services/media_service.dart';
import '../services/memory_repository.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import '../utils/photo_crop.dart';
import '../widgets/common/keyboard_aware.dart';
import '../widgets/memory/form_top_bar.dart';
import '../widgets/memory_save/save_options_sheet.dart' show memoryDateLabel;
import 'date_time_picker_screen.dart';

/// Потолок письма. Не защита от длинного текста, а защита от вставленной
/// книги: запись едет в json-поле `data` и оседает в локальном кэше.
const int kCapsuleLetterMax = 10000;

/// Композер «Капсулы времени»: письмо и/или фото, запечатанные до выбранной даты.
/// Создаёт обычное воспоминание с флагами `sealed`+`openAt` (лента прячет его до
/// даты, затем раскрывает) и планирует локальное уведомление на день открытия.
///
/// Вариант А «Письмо на листе» из макета
/// https://claude.ai/artifact/P1TYH5PFd6RLu7R3UJi3yz (14.10.2026): шапка и
/// кнопка внизу как у экрана записи, письмо пишется на листе пина-заметки —
/// так оно и откроется в ленте, срок показан крупным числом дней.
class TimeCapsuleScreen extends StatefulWidget {
  final AppTheme theme;
  final String pairId;
  final String authorName;
  final String authorAvatar;

  /// Часы экрана. Тесты и снимки задают свои, чтобы число дней не плыло.
  @visibleForTesting
  final DateTime Function()? now;

  /// Фото, уже лежащее в капсуле: для снимков экрана, где галереи нет.
  @visibleForTesting
  final String? previewPhotoPath;

  const TimeCapsuleScreen({
    super.key,
    required this.theme,
    required this.pairId,
    required this.authorName,
    required this.authorAvatar,
    this.now,
    this.previewPhotoPath,
  });

  @override
  State<TimeCapsuleScreen> createState() => _TimeCapsuleScreenState();
}

class _TimeCapsuleScreenState extends State<TimeCapsuleScreen> {
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String? _photoPath;
  late DateTime _openAt;
  bool _saving = false;

  AppTheme get _t => widget.theme;

  /// Схема M3 экрана: цвета берём ролями, а не из старой темы.
  ColorScheme get _cs => ProfileTheme.themeFor(_t).colorScheme;

  /// Что писать поверх заливки темы: правило одно на всё приложение.
  Color get _onFill => AppThemes.onColor(_t.fillColor, mode: _t.brightness);

  DateTime _clock() => (widget.now ?? DateTime.now)();

  /// Насколько кавычка поднимается над листом письма — как у пина-заметки.
  static const double _quoteLift = 22;

  @override
  void initState() {
    super.initState();
    // По умолчанию — через полгода.
    _openAt = capsulePresetDate(_clock(), CapsulePreset.halfYear);
    _photoPath = widget.previewPhotoPath;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final s = LocaleService.current;
    final media = MediaQuery.of(context);
    // Клавиатуру видно только снаружи Scaffold: своему body он отдаёт нулевой
    // отступ. На время набора кнопка внизу прячется, иначе письмо уезжает под
    // неё.
    final typing = keyboardOpen(context);

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(height: media.padding.top + 8),
                FormTopBar(
                  scheme: cs,
                  dot: _t.fillColor,
                  label: s.timeCapsule,
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        12, 6, 12, 108 + media.padding.bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _hint(cs, s),
                        const SizedBox(height: 14),
                        _letter(cs, s),
                        const SizedBox(height: 12),
                        _photo(cs, s),
                        const SizedBox(height: 12),
                        _when(cs, s),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (!typing)
              Positioned(
                left: 12,
                right: 12,
                bottom: media.padding.bottom + 12,
                child: _sealButton(cs, s),
              ),
          ],
        ),
      ),
    );
  }

  /// Подсказка под шапкой, как под плёнкой экрана записи.
  Widget _hint(ColorScheme cs, AppStrings s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.capsuleIntro,
              style: AppFonts.onest(size: 13, weight: 500, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// Поле без своей подложки: лист уже даёт и цвет, и форму.
  InputDecoration _bare(String hint, TextStyle style) => InputDecoration(
        hintText: hint,
        hintStyle: style,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      );

  /// Письмо на листе пина-заметки: тот же `secondaryContainer`, радиус 28 и
  /// кавычка цвета темы над краем, что у `NotePin`. Что человек пишет, так оно
  /// и откроется в ленте.
  Widget _letter(ColorScheme cs, AppStrings s) {
    final ink = cs.onSecondaryContainer;
    final hint = ink.withValues(alpha: 0.6);
    final titleStyle = AppFonts.onest(size: 18, weight: 700, color: ink);
    final bodyStyle = AppFonts.onest(size: 17, height: 1.45, color: ink);
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _quoteLift),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('capsule-title'),
                  controller: _titleCtrl,
                  maxLength: 120,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: titleStyle,
                  cursorColor: ink,
                  decoration: _bare(s.titleHint, titleStyle.copyWith(color: hint))
                      .copyWith(counterText: ''),
                ),
                const SizedBox(height: 8),
                // Письмо в будущее пишут не подписью к фото: 800 символов
                // обрывали его на полуслове. Поле растёт вместе с текстом,
                // а счётчик появляется на последней тысяче.
                TextField(
                  key: const ValueKey('capsule-letter'),
                  controller: _msgCtrl,
                  minLines: 6,
                  maxLines: null,
                  maxLength: kCapsuleLetterMax,
                  buildCounter: _counter,
                  textCapitalization: TextCapitalization.sentences,
                  style: bodyStyle,
                  cursorColor: ink,
                  decoration: _bare(s.capsuleLetterHint, bodyStyle.copyWith(color: hint)),
                ),
              ],
            ),
          ),
        ),
        // Кавычка лежит поверх края листа и касаний не забирает.
        Positioned(
          left: 14,
          top: 0,
          child: IgnorePointer(
            child: Text(
              '“',
              style: TextStyle(
                fontFamily: ProfileTheme.displayFont,
                fontSize: 88,
                fontWeight: FontWeight.w800,
                height: 1,
                color: _t.fillColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Счётчик молчит, пока запас велик, и подсказывает на последней тысяче.
  Widget? _counter(BuildContext context,
      {required int currentLength,
      required int? maxLength,
      required bool isFocused}) {
    final limit = maxLength ?? kCapsuleLetterMax;
    if (limit - currentLength > 1000) return const SizedBox.shrink();
    return Text(
      '$currentLength / $limit',
      style: AppFonts.onest(
          size: 12, weight: 600, color: _cs.onSecondaryContainer.withValues(alpha: 0.7)),
    );
  }

  /// Пустая плитка, как у экрана записи; выбранный снимок — кадром со
  /// снятием в углу.
  Widget _photo(ColorScheme cs, AppStrings s) {
    final path = _photoPath;
    if (path == null) {
      return Material(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pickPhoto,
          child: SizedBox(
            height: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_rounded, size: 28, color: cs.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    s.capsuleAttachPhoto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.onest(size: 15, weight: 600, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final decode = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: decode,
              errorBuilder: (_, _, _) => ColoredBox(color: cs.surfaceContainerHigh),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Tooltip(
                message: s.deletePhoto,
                child: Material(
                  color: cs.inverseSurface,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => setState(() => _photoPath = null),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.close_rounded,
                          size: 20, color: cs.onInverseSurface),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Срок: крупное число дней, дата открытия и быстрые кнопки связанной
  /// группой M3 Expressive. Кнопка с календарём открывает барабаны.
  Widget _when(ColorScheme cs, AppStrings s) {
    final now = _clock();
    final days = capsuleDaysLeft(_openAt, now);
    final preset = capsulePresetOf(_openAt, now);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_openAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Подпись нарочно в две строки: «дня» и «до открытия». Не влезает
          // рядом с числом (немецкий, крупный шрифт, капсула на годы) —
          // уходит под него целиком, а не рвётся посреди слова.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 6,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$days',
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: ProfileTheme.displayFont,
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      height: 0.86,
                      letterSpacing: -2.9,
                      color: cs.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.tgYearDaysUnit(days),
                        style: AppFonts.onest(size: 17, weight: 700, color: cs.onSurface),
                      ),
                      Text(
                        s.capsuleUntilOpen,
                        style: AppFonts.onest(
                            size: 14, weight: 500, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${memoryDateLabel(_openAt)}, $time',
                    style: AppFonts.onest(size: 14, weight: 600, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _presets(cs, s, preset)),
              const SizedBox(width: 8),
              _customDate(cs, s, selected: preset == null),
            ],
          ),
        ],
      ),
    );
  }

  /// Связанная группа «Месяц · Полгода · Год»: внутренние углы малые,
  /// внешние круглые, выбранная кнопка скругляется целиком.
  Widget _presets(ColorScheme cs, AppStrings s, CapsulePreset? selected) {
    final items = [
      (CapsulePreset.month, s.capsulePreset1m),
      (CapsulePreset.halfYear, s.capsulePreset6m),
      (CapsulePreset.year, s.capsulePreset1y),
    ];
    return LayoutBuilder(builder: (context, c) {
      // Подписи уменьшаются вместе: одна мелкая «6 Monate» рядом с крупными
      // «Monat» и «Jahr» выглядела опечаткой.
      final size = _segmentFontSize(
        context,
        labels: [for (final i in items) i.$2],
        width: (c.maxWidth - 2 * (items.length - 1)) / items.length - 12,
      );
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: _segment(
                cs,
                label: items[i].$2,
                fontSize: size,
                on: selected == items[i].$1,
                first: i == 0,
                last: i == items.length - 1,
                onTap: () => setState(
                    () => _openAt = capsulePresetDate(_clock(), items[i].$1)),
              ),
            ),
          ],
        ],
      );
    });
  }

  /// Общий размер подписей кнопок срока: 14, а если самая длинная не влезает
  /// в кнопку — меньше, одинаково для всех.
  double _segmentFontSize(BuildContext context,
      {required List<String> labels, required double width}) {
    const base = 14.0;
    var size = base;
    for (final label in labels) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: AppFonts.onest(size: base, weight: 600)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (tp.width > width && tp.width > 0) {
        size = math.min(size, base * width / tp.width * 0.98);
      }
      tp.dispose();
    }
    return size;
  }

  Widget _segment(
    ColorScheme cs, {
    required String label,
    required double fontSize,
    required bool on,
    required bool first,
    required bool last,
    required VoidCallback onTap,
  }) {
    const full = Radius.circular(24);
    const inner = Radius.circular(8);
    final radius = on
        ? const BorderRadius.all(full)
        : BorderRadius.horizontal(
            left: first ? full : inner,
            right: last ? full : inner,
          );
    return Semantics(
      button: true,
      selected: on,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: on ? _t.fillColor : cs.surface,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppFonts.onest(
                        size: fontSize, weight: 600, color: on ? _onFill : cs.onSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Своя дата барабанами; кнопка залита, когда срок не совпал ни с одним
  /// быстрым.
  Widget _customDate(ColorScheme cs, AppStrings s, {required bool selected}) {
    return Tooltip(
      message: s.capsuleOpenDate,
      child: Material(
        color: selected ? _t.fillColor : cs.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _pickDate,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.edit_calendar_rounded,
                size: 22, color: selected ? _onFill : cs.onSurface),
          ),
        ),
      ),
    );
  }

  /// Кнопка внизу поверх прокрутки, как «Сохранить» у экрана записи. Пустую
  /// капсулу запечатать нельзя: кнопка молчит, пока нет письма или фото.
  Widget _sealButton(ColorScheme cs, AppStrings s) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _msgCtrl,
      builder: (context, value, _) {
        final can = value.text.trim().isNotEmpty || _photoPath != null;
        // Во время заливки кнопка не гаснет, а просто не принимает касаний:
        // крутилка видна на заливке темы.
        return IgnorePointer(
          ignoring: _saving,
          child: FilledButton.icon(
            key: const ValueKey('capsule-seal'),
            onPressed: can ? _seal : null,
            icon: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: cs.onPrimary),
                  )
                : const Icon(Icons.lock_rounded, size: 22),
            label: Text(s.capsuleSeal),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final XFile? x = await safePick(
      () => picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1920,
        maxHeight: 1920,
      ),
    );
    if (x == null) return;
    final cropped = await cropPhoto(x.path, accentColor: _t.primary);
    if (!mounted) return;
    setState(() => _photoPath = cropped ?? x.path);
  }

  Future<void> _pickDate() async {
    final now = _clock();
    final picked = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => DateTimePickerScreen(
          title: LocaleService.current.capsuleOpenDate,
          theme: _t,
          initial: _openAt.isAfter(now) ? _openAt : now.add(const Duration(days: 1)),
          firstYear: now.year,
          lastYear: now.year + 10,
          // Час открытия фиксированный (девять утра), время выбирать нечего.
          withTime: false,
        ),
        settings: const RouteSettings(name: '/date_picker'),
      ),
    );
    if (picked == null || !mounted) return;
    final at = DateTime(picked.year, picked.month, picked.day, kCapsuleOpenHour);
    // Дату из прошлого барабан отдать может (год начинается с нынешнего) —
    // проверку оставляем здесь: она же ловит и «сегодня».
    if (!at.isAfter(_clock()) || capsuleDaysLeft(at, _clock()) < 1) {
      _snack(LocaleService.current.capsuleNeedsFutureDate);
      return;
    }
    setState(() => _openAt = at);
  }

  Future<void> _seal() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty && _photoPath == null) {
      _snack(LocaleService.current.capsuleNeedsContent);
      return;
    }
    if (!_openAt.isAfter(_clock())) {
      _snack(LocaleService.current.capsuleNeedsFutureDate);
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl;
      var type = MemoryType.text;
      if (_photoPath != null) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final ext = _photoPath!.split('.').last;
        imageUrl = await MediaService()
            .uploadFile(_photoPath!, 'memories/${widget.pairId}/capsule_$ts.$ext');
        if (imageUrl == null) {
          if (mounted) {
            setState(() => _saving = false);
            _snack(LocaleService.current.failedUploadPhoto);
          }
          return;
        }
        type = MemoryType.photo;
      }
      final title = _titleCtrl.text.trim();
      final created = await MemoryRepository().add(
        groupId: widget.pairId,
        authorName: widget.authorName,
        authorAvatar: widget.authorAvatar,
        type: type,
        imageUrl: imageUrl,
        title: title.isEmpty ? null : title,
        caption: msg.isEmpty ? null : msg,
        sealed: true,
        openAt: _openAt,
      );
      // Уведомление планируем в фоне — не держим закрытие экрана на платформенном
      // вызове (мог зависнуть на запросе разрешения → композер «крутился»).
      if (created != null) {
        unawaited(CapsuleNotificationService.instance
            .schedule(created.id, _openAt, capsuleTitle: title));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Error: $e');
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ));
  }
}
