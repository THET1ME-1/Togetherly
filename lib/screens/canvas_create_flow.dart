import 'package:flutter/material.dart';

import '../models/canvas_meta.dart';
import '../models/coloring_join.dart';
import '../models/pair_data.dart';
import '../models/user_data.dart';
import '../services/canvas_repository.dart';
import '../services/canvas_storage_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sheet.dart';
import 'coloring_catalogue_screen.dart';
import 'draw_screen.dart';
import 'pixel_size_screen.dart';

/// Создание холста: выбор вида, подготовка и открытие рисовалки.
///
/// Один путь на всё приложение. Раньше главная по «Новому холсту» молча
/// заводила пустой лист, а выбор вида жил только в галерее рисунков — до
/// раскраски приходилось идти через «Мои рисунки» и кнопку создания там.
/// Люди её просто не находили и писали, что раскраски в приложении нет
/// (жалоба 30 июля), хотя она стояла на месте и никакими замками закрыта не
/// была.
class CanvasCreateFlow {
  const CanvasCreateFlow._();

  /// Спрашивает вид холста и доводит до открытой рисовалки.
  ///
  /// Возвращает true, если холст создан: галерее по этому признаку нужно
  /// перечитать список.
  static Future<bool> start(
    BuildContext context, {
    required UserData userData,
    required PairData pairData,
    required AppTheme theme,
    required CanvasStorageService storage,
  }) async {
    final kind = await _askKind(context, theme);
    if (kind == null || !context.mounted) return false;

    final s = LocaleService.current;
    final uid = userData.uid;
    final groupId = pairData.pairId;

    if (kind == _CanvasKind.coloring) {
      final choice = await Navigator.push<ColoringChoice>(
        context,
        MaterialPageRoute(
          builder: (_) => ColoringCatalogueScreen(theme: theme),
          settings: const RouteSettings(name: '/coloring_catalogue'),
        ),
      );
      if (choice == null || !context.mounted) return false;

      // Пара выбирает одну картинку почти одновременно, и раньше каждый
      // получал свой лист: у обоих закрашена своя половина, вторая пустая
      // (пара rc3eb70972c9644 — одиннадцать листов «Кафе», ни одного общего).
      // Уже начатый лист той же картинки предлагаем открыть.
      final started = await _startedSheet(
        userData: userData,
        pairData: pairData,
        pictureId: choice.picture.id,
      );
      if (!context.mounted) return false;
      if (started != null) {
        final join = await _askJoin(context, theme, started.name);
        if (join == null || !context.mounted) return false;
        if (join) {
          // Без `coloring`: иначе рисовалка заново заведёт раскраску на листе
          // и сотрёт партнёру его «Готово» и режим. Картинку, режим и
          // половины экран подхватит из `canvas_meta` сам.
          await _open(context,
              userData: userData,
              pairData: pairData,
              theme: theme,
              meta: started);
          return true;
        }
      }
      if (!context.mounted) return false;
      // Лист квадратный: раскраска нарисована 1:1, иначе половины перестали бы
      // совпадать с контуром.
      final meta = await storage.createCanvas(
        uid,
        name: choice.picture.title,
        groupId: groupId,
        sheetRatio: 1.0,
      );
      if (!context.mounted) return false;
      await _open(context,
          userData: userData,
          pairData: pairData,
          theme: theme,
          meta: meta,
          coloring: choice);
      return true;
    }

    (int, int)? grid;
    if (kind == _CanvasKind.pixel) {
      grid = await Navigator.push<(int, int)>(
        context,
        MaterialPageRoute(
          builder: (_) => PixelSizeScreen(theme: theme),
          settings: const RouteSettings(name: '/pixel_size'),
        ),
      );
      if (grid == null || !context.mounted) return false;
    }

    final existing = await storage.getCanvases(uid, groupId: groupId);
    final meta = await storage.createCanvas(
      uid,
      name: '${s.untitledCanvas} ${existing.length + 1}',
      groupId: groupId,
      pixelW: grid?.$1,
      pixelH: grid?.$2,
    );
    if (!context.mounted) return false;
    await _open(context,
        userData: userData, pairData: pairData, theme: theme, meta: meta);
    return true;
  }

  /// Уже начатый лист раскраски [pictureId] у этой пары или null.
  ///
  /// Спрашивает сервер, а не локальный список: лист, заведённый партнёром
  /// секунды назад, в локальный доезжает только при открытой галерее. Сеть
  /// молчит — не держим человека, заводим новый лист как раньше.
  static Future<CanvasMeta?> _startedSheet({
    required UserData userData,
    required PairData pairData,
    required String pictureId,
  }) async {
    final groupId = pairData.pairId;
    if (groupId.isEmpty) return null;
    try {
      final found = await CanvasRepository()
          .coloringSheets(groupId)
          .timeout(const Duration(seconds: 4));
      final sheet = coloringSheetToJoin(
        found.sheets,
        pictureId: pictureId,
        members: [userData.uid, pairData.partnerUid],
        listed: found.catalogue.keys.toSet(),
        now: DateTime.now(),
      );
      return sheet == null ? null : found.catalogue[sheet.canvasId];
    } catch (e) {
      debugPrint('раскраска: начатый лист не нашли: $e');
      return null;
    }
  }

  /// true — открыть начатый лист, false — завести новый, null — передумал.
  static Future<bool?> _askJoin(
      BuildContext context, AppTheme t, String name) {
    final s = LocaleService.current;
    return showAppSheet<bool>(
      context,
      background: t.cardSurface,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              s.coloringJoinTitle,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.coloringJoinBody(name),
              style: TextStyle(fontSize: 15, color: t.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(s.coloringJoinOpen, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(s.coloringJoinNew, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _open(
    BuildContext context, {
    required UserData userData,
    required PairData pairData,
    required AppTheme theme,
    required CanvasMeta meta,
    ColoringChoice? coloring,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrawScreen(
          userData: userData,
          pairData: pairData,
          theme: theme,
          canvasId: meta.id,
          canvasName: meta.name,
          pixelW: meta.pixelW,
          pixelH: meta.pixelH,
          sheetRatio: coloring != null ? 1.0 : meta.effectiveRatio,
          coloringId: coloring?.picture.id,
          coloringMode: coloring?.mode,
        ),
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/draw'),
      ),
    );
  }

  static Future<_CanvasKind?> _askKind(BuildContext context, AppTheme t) {
    final s = LocaleService.current;
    return showModalBottomSheet<_CanvasKind>(
      context: context,
      backgroundColor: t.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                s.newCanvas,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              _tile(
                t,
                icon: Icons.brush_rounded,
                title: s.plainCanvas,
                subtitle: s.plainCanvasSubtitle,
                onTap: () => Navigator.pop(ctx, _CanvasKind.plain),
              ),
              const SizedBox(height: 10),
              _tile(
                t,
                icon: Icons.grid_on_rounded,
                title: s.pixelCanvasCreate,
                subtitle: s.pixelCanvasSubtitle,
                onTap: () => Navigator.pop(ctx, _CanvasKind.pixel),
              ),
              const SizedBox(height: 10),
              _tile(
                t,
                icon: Icons.palette_rounded,
                title: s.coloringTitle,
                subtitle: s.coloringSubtitle,
                onTap: () => Navigator.pop(ctx, _CanvasKind.coloring),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _tile(
    AppTheme t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.surfaceMuted,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: t.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CanvasKind { plain, pixel, coloring }
