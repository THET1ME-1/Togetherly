import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/coloring_picture.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';

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

  AppStrings get _s => LocaleService.current;

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
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemCount: ColoringPicture.all.length,
              itemBuilder: (_, i) => _card(cs, ColoringPicture.all[i]),
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
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
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
