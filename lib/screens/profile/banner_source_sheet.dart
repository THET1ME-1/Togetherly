import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/plus_access.dart';
import '../../theme/profile_theme.dart';
import '../../widgets/app_sheet.dart';

/// Откуда взять баннер профиля.
enum BannerSource { camera, gallery, gif }

/// Лист смены баннера: камера, галерея и GIF.
///
/// GIF — вещь Togetherly+. Без Плюса строка стоит с замком и подписью
/// «Togetherly+»: человек видит, что так можно, а нажатие ведёт на витрину
/// (это решает экран, который открыл лист). Где Плюса не существует
/// ([PlusGate.hidden]), строки нет вовсе.
Future<BannerSource?> showBannerSourceSheet(
  BuildContext context, {
  required ColorScheme cs,
  required PlusGate gifGate,
}) {
  return showAppSheet<BannerSource>(
    context,
    background: cs.surfaceContainerHigh,
    builder: (_) => BannerSourceSheet(cs: cs, gifGate: gifGate),
  );
}

/// Содержимое листа [showBannerSourceSheet]: отдельный виджет, чтобы его
/// можно было снять тестом без экрана профиля.
class BannerSourceSheet extends StatelessWidget {
  const BannerSourceSheet({super.key, required this.cs, required this.gifGate});

  final ColorScheme cs;
  final PlusGate gifGate;

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final locked = gifGate == PlusGate.locked;
    return SheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(
            context,
            icon: Icons.photo_camera_rounded,
            title: s.photoFromCamera,
            value: BannerSource.camera,
          ),
          _tile(
            context,
            icon: Icons.photo_library_rounded,
            title: s.photoFromGallery,
            value: BannerSource.gallery,
          ),
          if (gifGate != PlusGate.hidden)
            _tile(
              context,
              icon: Icons.gif_box_rounded,
              title: s.bannerGif,
              value: BannerSource.gif,
              subtitle: locked ? 'Togetherly+' : null,
              trailing: locked
                  ? Icon(
                      Icons.lock_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required BannerSource value,
    String? subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: cs.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: ProfileTheme.bodyFont,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                fontFamily: ProfileTheme.bodyFont,
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
      trailing: trailing,
      onTap: () => Navigator.pop(context, value),
    );
  }
}
