import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../theme/profile_theme.dart';
import 'app_sheet.dart';
import 'avatar_widget.dart';
import 'storage_image.dart';

/// Содержимое парного виджета целиком: письмо, песня, снимок.
///
/// Карточка на экране виджетов показывает обрезок — строка текста с
/// многоточием, миниатюра в 46 пикселей, название трека без обложки. Раскрыть
/// это было негде: половина партнёра рисовалась глухим `Container` без отклика,
/// и длинное сообщение человек не дочитывал никогда.
///
/// Всё открывается нижними листами ([showAppSheet]), а снимок — отдельным
/// чёрным экраном с зумом: диалог по центру тут не годится ни по правилам
/// проекта, ни по размеру содержимого.

/// Письмо или статус целиком. Текст крупный, автор подписывает снизу.
///
/// [quoted] ставит над текстом крупную кавычку — она нужна письму, где слова
/// обращены к тебе, и лишняя у статуса из трёх слов.
Future<void> showWidgetTextSheet(
  BuildContext context, {
  required AppTheme theme,
  required String title,
  required String text,
  required String authorUid,
  String? authorName,
  String? authorAvatarUrl,
  DateTime? updatedAt,
  bool quoted = false,
}) {
  // Тему и строки снимаем ДО открытия листа: он переживает экран, а обращение
  // к мёртвому состоянию проекту уже дорого обходилось.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final media = MediaQuery.of(context);

  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerHigh,
    builder: (_) => SheetScaffold(
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (quoted)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '«',
                  style: AppFonts.unbounded(
                    size: 34,
                    weight: 700,
                    height: 0.9,
                    color: scheme.primary,
                  ),
                ),
              ),
            // Длинное письмо прокручивается внутри листа, а не растит его до
            // потолка экрана.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.52),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: AppFonts.onest(
                    size: 19,
                    weight: 500,
                    height: 1.42,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _AuthorLine(
              scheme: scheme,
              uid: authorUid,
              name: authorName,
              avatarUrl: authorAvatarUrl,
              updatedAt: updatedAt,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Песня целиком: обложка во всю ширину, название и исполнитель без обрезки.
///
/// Обложка приходит не всегда ([coverUrl] пуст у трека, вписанного руками), и
/// тогда широкий блок с одной нотой выглядел бы поломкой — на этот случай
/// вёрстка сжимается до квадрата рядом с текстом.
Future<void> showWidgetMusicSheet(
  BuildContext context, {
  required AppTheme theme,
  required String title,
  String? artist,
  String? coverUrl,
  required String authorUid,
  String? authorName,
  String? authorAvatarUrl,
  DateTime? updatedAt,
}) {
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  final s = LocaleService.current;
  final hasCover = coverUrl != null && coverUrl.isNotEmpty;

  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainerHigh,
    builder: (_) => SheetScaffold(
      title: s.music,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCover) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: StorageImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, __) => _CoverStub(scheme: scheme),
                    errorWidget: (_, __, ___) => _CoverStub(scheme: scheme),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _TrackText(scheme: scheme, title: title, artist: artist),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: _CoverStub(scheme: scheme),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _TrackText(
                      scheme: scheme,
                      title: title,
                      artist: artist,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            _AuthorLine(
              scheme: scheme,
              uid: authorUid,
              name: authorName,
              avatarUrl: authorAvatarUrl,
              updatedAt: updatedAt,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Снимок на весь экран: щипок увеличивает, свайп вниз закрывает.
Future<void> openWidgetPhotoView(
  BuildContext context, {
  required String imageUrl,
  String? authorName,
  DateTime? updatedAt,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: _PhotoView(
          imageUrl: imageUrl,
          authorName: authorName,
          updatedAt: updatedAt,
        ),
      ),
    ),
  );
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({
    required this.imageUrl,
    this.authorName,
    this.updatedAt,
  });

  final String imageUrl;
  final String? authorName;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final caption = _captionOf(authorName, updatedAt);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      style: AppFonts.onest(
                        size: 13,
                        weight: 600,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                // Свайп вниз закрывает — привычка от любой галереи. Порог по
                // скорости, чтобы не ловить его на щипке.
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) {
                    Navigator.of(context).pop();
                  }
                },
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: StorageImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white54,
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white38,
                        size: 48,
                      ),
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
}

/// Кто и когда — подпись под содержимым.
class _AuthorLine extends StatelessWidget {
  const _AuthorLine({
    required this.scheme,
    required this.uid,
    this.name,
    this.avatarUrl,
    this.updatedAt,
  });

  final ColorScheme scheme;
  final String uid;
  final String? name;
  final String? avatarUrl;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final who = (name ?? '').trim();
    final when = updatedAt == null ? '' : _timeAgo(updatedAt!);

    return Row(
      children: [
        AvatarWidget(
          uid: uid,
          liveUrl: avatarUrl,
          name: who,
          size: 30,
          primary: scheme.primary,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            who.isEmpty ? LocaleService.current.partner : who,
            style: AppFonts.onest(
              size: 13,
              weight: 600,
              color: scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (when.isNotEmpty)
          Text(
            when,
            style: AppFonts.onest(
              size: 11,
              weight: 500,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _TrackText extends StatelessWidget {
  const _TrackText({
    required this.scheme,
    required this.title,
    this.artist,
  });

  final ColorScheme scheme;
  final String title;
  final String? artist;

  @override
  Widget build(BuildContext context) {
    final performer = (artist ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppFonts.onest(
            size: 19,
            weight: 700,
            height: 1.25,
            color: scheme.onSurface,
          ),
        ),
        if (performer.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            performer,
            style: AppFonts.onest(
              size: 14,
              weight: 500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CoverStub extends StatelessWidget {
  const _CoverStub({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.music_note_rounded, size: 30, color: scheme.primary),
    );
  }
}

String _captionOf(String? name, DateTime? updatedAt) {
  final who = (name ?? '').trim();
  final when = updatedAt == null ? '' : _timeAgo(updatedAt);
  if (who.isEmpty) return when;
  if (when.isEmpty) return who;
  return '$who · $when';
}

/// «12 мин. назад» на языке приложения.
String _timeAgo(DateTime dt) {
  final s = LocaleService.current;
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return s.justNow;
  if (diff.inMinutes < 60) return s.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return s.hoursAgo(diff.inHours);
  if (diff.inDays < 30) return s.daysAgo(diff.inDays);
  return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}
