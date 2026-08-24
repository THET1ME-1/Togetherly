import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../models/coloring_picture.dart';
import '../services/coloring_upload_queue.dart';
import '../services/plus_access.dart';
import '../services/plus_service.dart';
import '../utils/safe_pick.dart';
import '../widgets/common/m3_loading.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';
import 'plus_screen.dart';

/// Что выбрали в каталоге раскрасок.
class ColoringChoice {
  const ColoringChoice({required this.picture, required this.mode});

  final ColoringPicture picture;
  final ColoringMode mode;
}

/// Каталог раскрасок: картинка плюс режим на двоих.
///
/// Режим выбирается один раз, до начала: он один на рисунок и виден обоим.
/// Переключать его на полпути нельзя — иначе «сюрприз» терял бы смысл ровно в
/// тот момент, когда кому-то стало любопытно.
class ColoringCatalogueScreen extends StatefulWidget {
  const ColoringCatalogueScreen({super.key, required this.theme});

  final AppTheme theme;

  @override
  State<ColoringCatalogueScreen> createState() =>
      _ColoringCatalogueScreenState();
}

class _ColoringCatalogueScreenState extends State<ColoringCatalogueScreen> {
  ColoringMode _mode = ColoringMode.surprise;

  final ColoringUploadQueue _uploads = ColoringUploadQueue.instance;

  AppStrings get _s => LocaleService.current;

  bool get _ru => LocaleService.instance.isRussian;

  String _tr(String ru, String en) => _ru ? ru : en;

  /// Свои рисунки открывает Togetherly+.
  ///
  /// Решает общий `PlusAccess.gate`, а не связка «активен и не iOS»:
  ///   • `open` — загрузка работает, в том числе у оплатившего с Android,
  ///     который зашёл с iPhone (флаг живёт на аккаунте, купленное открыто
  ///     везде — прежний `!Platform.isIOS` прятал у него собственные рисунки);
  ///   • `locked` — плитка на месте, но с замком и переходом на экран Плюса.
  ///     Раньше её просто не рисовали, и о самой возможности человек не узнавал;
  ///   • `hidden` — Плюса на платформе нет как понятия (iOS у некупившего),
  ///     плитки нет вовсе: вести на внешнюю оплату запрещает 3.1.1.
  PlusGate get _gate => PlusService.instance.gate;

  /// Показывать ли свои рисунки — и уже загруженные, и плитку добавления.
  bool get _ownVisible => _gate != PlusGate.hidden;

  /// Уже загруженные рисунки остаются на месте и после того, как Плюс кончился:
  /// они лежат на устройстве, и прятать их задним числом значит отобрать
  /// сделанное. Закрыта только загрузка новых.
  List<ColoringUpload> get _ownItems =>
      _ownVisible ? _uploads.items : const [];

  @override
  void initState() {
    super.initState();
    _uploads.addListener(_onUploads);
    unawaited(_uploads.resume());
  }

  @override
  void dispose() {
    _uploads.removeListener(_onUploads);
    super.dispose();
  }

  void _onUploads() {
    if (mounted) setState(() {});
  }

  /// Берём картинку и сразу отдаём управление: обработка идёт в стороне, а
  /// карточка появляется в сетке в ту же секунду с пометкой «готовим».
  Future<void> _pickOwn() async {
    if (_gate != PlusGate.open) {
      // Стена: сначала экран Плюса, галерею не открываем вовсе.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PlusScreen(scheme: ProfileTheme.themeFor(widget.theme).colorScheme),
          settings: const RouteSettings(name: '/plus'),
        ),
      );
      return;
    }
    final picked = await safePick(
      () => ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 100),
    );
    if (picked == null || !mounted) return;
    await _uploads.add(File(picked.path), title: _s.coloringOwnDefaultName);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(widget.theme);
    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            _s.coloringTitle,
            style: TextStyle(
              fontFamily: 'Unbounded',
              fontSize: 19,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
              color: cs.onSurface,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          children: [
            _modeSwitch(cs),
            const SizedBox(height: 10),
            Text(
              _mode == ColoringMode.surprise
                  ? _s.coloringModeSurpriseHint
                  : _s.coloringModeTogetherHint,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              // Запас прогрева: без него ряд за краем экрана начинал готовиться
              // ровно тогда, когда его уже листают.
              cacheExtent: 600,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: ColoringPicture.all.length +
                  (_ownVisible ? _ownItems.length + 1 : 0),
              itemBuilder: (_, i) {
                if (!_ownVisible) return _card(cs, ColoringPicture.all[i]);
                if (i == 0) return _addOwnCard(cs);
                final own = i - 1;
                if (own < _ownItems.length) {
                  return _ownCard(cs, _ownItems[own]);
                }
                return _card(
                    cs, ColoringPicture.all[i - 1 - _ownItems.length]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeSwitch(ColorScheme cs) {
    Widget seg(String label, ColoringMode mode) {
      final active = _mode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _mode = mode);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          seg(_s.coloringModeSurprise, ColoringMode.surprise),
          seg(_s.coloringModeTogether, ColoringMode.together),
        ],
      ),
    );
  }


  /// Кнопка «загрузить свою» — такой же плиткой, чтобы сетка не рвалась.
  Widget _addOwnCard(ColorScheme cs) {
    final locked = _gate != PlusGate.open;
    return Material(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _pickOwn,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              locked
                  ? Icons.lock_rounded
                  : Icons.add_photo_alternate_rounded,
              size: 34,
              color: cs.onPrimaryContainer,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _s.coloringOwnAdd,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
            // Замок без объяснения читается как поломка, поэтому под ним
            // сказано, что открывает эту плитку.
            if (locked) ...[
              const SizedBox(height: 4),
              Text(
                _tr('в Togetherly+', 'in Togetherly+'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer.withValues(alpha: .75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Своя раскраска: пока считается — круговой индикатор прямо в плитке,
  /// приложением при этом можно пользоваться дальше.
  Widget _ownCard(ColorScheme cs, ColoringUpload item) {
    final failed = item.status == ColoringUploadStatus.failed;
    return Material(
      color: failed ? cs.errorContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.isReady
            ? () => Navigator.pop(
                  context,
                  ColoringChoice(
                    picture: ColoringPicture.own(
                      id: item.id,
                      title: item.title,
                      ratio: item.ratio,
                    ),
                    mode: _mode,
                  ),
                )
            : null,
        onLongPress: () => _uploads.remove(item.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.status == ColoringUploadStatus.processing)
                M3Loading(size: 40, color: cs.primary)
              else
                Icon(
                  failed ? Icons.error_outline_rounded : Icons.brush_rounded,
                  size: 32,
                  color: failed ? cs.onErrorContainer : cs.primary,
                ),
              const SizedBox(height: 10),
              Text(
                failed ? item.error : item.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: failed ? cs.onErrorContainer : cs.onSurface,
                ),
              ),
              if (item.status == ColoringUploadStatus.processing) ...[
                const SizedBox(height: 4),
                Text(
                  _s.coloringOwnProcessing,
                  style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 11,
                      color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(ColorScheme cs, ColoringPicture picture) {
    return Material(
      color: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => Navigator.pop(
          context,
          ColoringChoice(picture: picture, mode: _mode),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                child: Image.asset(picture.thumbAsset, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                picture.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
