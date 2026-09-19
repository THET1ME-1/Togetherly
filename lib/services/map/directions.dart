import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/fonts.dart';
import '../../utils/safe_launch.dart';
import '../../widgets/app_sheet.dart';
import '../locale_service.dart';

/// Приложения карт на iPhone: системного выбора там нет, поэтому список
/// строим сами — из того, что реально установлено. Apple Карты есть всегда.
List<({String name, Uri uri})> iosMapApps(LatLng to) {
  final ll = '${to.latitude},${to.longitude}';
  return [
    (name: 'Apple Maps', uri: Uri.parse('https://maps.apple.com/?daddr=$ll')),
    (name: 'Google Maps', uri: Uri.parse('comgooglemaps://?daddr=$ll')),
    (name: 'Яндекс Карты', uri: Uri.parse('yandexmaps://maps.yandex.ru/?rtext=~$ll')),
    (name: '2GIS', uri: Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/${to.longitude},${to.latitude}')),
  ];
}

/// Ссылка `geo:` для Android: приложение выбирает система — Яндекс Карты,
/// 2ГИС, Google, Organic Maps, что стоит у человека. Маршрут строит само
/// приложение карт от текущего места.
Uri androidGeoUri(LatLng to, String label) {
  final ll = '${to.latitude},${to.longitude}';
  final name = label.trim().isEmpty ? '' : '(${Uri.encodeComponent(label.trim())})';
  return Uri.parse('geo:$ll?q=$ll$name');
}

/// «Как доехать» до последней точки партнёра.
Future<void> openDirections(BuildContext context, LatLng to, String label) async {
  final s = LocaleService.current;
  if (!Platform.isIOS) {
    final ok = await safeLaunchUrl(androidGeoUri(to, label));
    if (!ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.liveMapRouteNoApp)));
    }
    return;
  }
  final apps = <({String name, Uri uri})>[];
  for (final app in iosMapApps(to)) {
    if (app.uri.scheme == 'https' || await canLaunchUrl(app.uri)) apps.add(app);
  }
  if (apps.length == 1) {
    await safeLaunchUrl(apps.first.uri);
    return;
  }
  if (!context.mounted) return;
  await showAppSheet<void>(
    context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SheetScaffold(
        title: s.liveMapRoute,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final app in apps)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      safeLaunchUrl(app.uri);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.map_rounded, color: cs.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              app.name,
                              style: AppFonts.onest(size: 16, weight: 600, color: cs.onSurface),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
