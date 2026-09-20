import 'package:flutter/material.dart';

import '../storage_image.dart';

/// Пропорции кадров, узнанные при загрузке.
///
/// В записи воспоминания хранятся только ссылки — ни ширины, ни высоты там
/// нет. Обложка в ленте показывается ЦЕЛИКОМ, в своей пропорции, поэтому
/// размер приходится узнавать у самой картинки и запоминать: иначе при каждой
/// прокрутке карточка прыгала бы с запасной пропорции на настоящую.
///
/// Кэш живёт в памяти процесса и намеренно не чистится: это пара чисел на
/// ссылку, а список кадров у пары конечен.
class MediaAspectCache {
  MediaAspectCache._();

  static final Map<String, double> _cache = {};

  static double? of(String url) => _cache[url];

  static void put(String url, double aspect) {
    if (aspect.isFinite && aspect > 0) _cache[url] = aspect;
  }

  /// Пропорция для показа: слишком узкие и слишком широкие кадры зажимаются,
  /// иначе панорама 5:1 растянет карточку в нитку, а кадр 1:3 займёт экран.
  static double clampAspect(double aspect) => aspect.clamp(0.62, 2.6);
}

/// Обложка записи: кадр целиком, в своей пропорции, со скруглением 22.
///
/// Пока пропорция неизвестна, держит 4:3 — так карточка не дёргается при
/// первой загрузке. Узнав настоящую, перестраивается один раз.
class AspectCover extends StatefulWidget {
  const AspectCover({
    super.key,
    required this.url,
    this.provider,
    this.radius = 22,
    this.fallbackAspect = 4 / 3,
    this.overlay,
    this.maxHeight,
  });

  /// Ссылка на кадр. Для ещё не залитого файла ссылки нет — тогда
  /// передают [provider] с локальным файлом, а url служит ключом кэша.
  final String url;

  /// Готовый источник картинки: файл, выбранный в галерее.
  final ImageProvider? provider;
  final double radius;
  final double fallbackAspect;

  /// Метки поверх кадра: длительность ролика, число кадров.
  final Widget? overlay;

  /// Потолок высоты — чтобы вертикальный кадр не занимал весь экран ленты.
  final double? maxHeight;

  @override
  State<AspectCover> createState() => _AspectCoverState();
}

class _AspectCoverState extends State<AspectCover> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _aspect = MediaAspectCache.of(widget.url);
    if (_aspect == null && widget.provider != null) _askProvider();
  }

  @override
  void didUpdateWidget(covariant AspectCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _aspect = MediaAspectCache.of(widget.url);
      if (_aspect == null && widget.provider != null) _askProvider();
    }
  }

  /// У локального файла своего колбэка нет — спрашиваем размер у провайдера.
  void _askProvider() {
    widget.provider!.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((info, _) {
            _onSize(Size(
                info.image.width.toDouble(), info.image.height.toDouble()));
          }, onError: (_, __) {}),
        );
  }

  void _onSize(Size size) {
    if (size.height <= 0) return;
    final a = size.width / size.height;
    MediaAspectCache.put(widget.url, a);
    if (mounted && _aspect != a) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _aspect = a);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final raw = _aspect ?? widget.fallbackAspect;
    final aspect = MediaAspectCache.clampAspect(raw);
    Widget image = widget.provider != null
        ? Image(image: widget.provider!, fit: BoxFit.cover)
        : StorageImage(
            imageUrl: widget.url,
            fit: BoxFit.cover,
            memCacheWidth: 1000,
            onSize: _onSize,
            errorWidget: (_, __, ___) => ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Icon(Icons.broken_image_rounded,
                  color: cs.onSurfaceVariant, size: 26),
            ),
          );
    if (widget.overlay != null) {
      image = Stack(fit: StackFit.expand, children: [image, widget.overlay!]);
    }
    Widget box = AspectRatio(aspectRatio: aspect, child: image);
    if (widget.maxHeight != null) {
      box = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight!),
        child: box,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: box,
    );
  }
}

/// Один кадр плёнки: высота задана, ширина считается по пропорции кадра.
///
/// Широкий снимок занимает в ряду больше места, вертикальный — меньше, и
/// ничего не обрезается по краям.
class FilmFrame extends StatefulWidget {
  const FilmFrame({
    super.key,
    required this.url,
    this.provider,
    required this.height,
    this.radius = 8,
    this.overlay,
    this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final String url;

  /// Локальный файл — для экрана записи, где кадры ещё не залиты.
  final ImageProvider? provider;
  final double height;
  final double radius;
  final Widget? overlay;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  State<FilmFrame> createState() => _FilmFrameState();
}

class _FilmFrameState extends State<FilmFrame> {
  double? _aspect;

  @override
  void initState() {
    super.initState();
    _aspect = MediaAspectCache.of(widget.url);
    if (_aspect == null && widget.provider != null) _askProvider();
  }

  @override
  void didUpdateWidget(covariant FilmFrame old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _aspect = MediaAspectCache.of(widget.url);
      if (_aspect == null && widget.provider != null) _askProvider();
    }
  }

  void _askProvider() {
    widget.provider!.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((info, _) {
            _onSize(Size(
                info.image.width.toDouble(), info.image.height.toDouble()));
          }, onError: (_, __) {}),
        );
  }

  void _onSize(Size size) {
    if (size.height <= 0) return;
    final a = size.width / size.height;
    MediaAspectCache.put(widget.url, a);
    if (mounted && _aspect != a) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _aspect = a);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aspect = MediaAspectCache.clampAspect(_aspect ?? 1);
    final width = widget.height * aspect;
    Widget frame = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.provider != null)
              Image(image: widget.provider!, fit: BoxFit.cover)
            else
              StorageImage(
                imageUrl: widget.url,
                fit: BoxFit.cover,
                memCacheWidth: 400,
                onSize: _onSize,
                errorWidget: (_, __, ___) =>
                    ColoredBox(color: cs.surfaceContainerHighest),
              ),
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
    if (widget.selected) {
      frame = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: cs.primary, width: 3),
        ),
        child: frame,
      );
    }
    if (widget.onTap == null && widget.onLongPress == null) return frame;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: frame,
    );
  }
}

/// Хвостовая плитка плёнки: сколько кадров осталось за краем.
class FilmRestTile extends StatelessWidget {
  const FilmRestTile({
    super.key,
    required this.count,
    required this.height,
    required this.label,
    this.background,
    this.foreground,
    this.radius = 8,
    this.onTap,
  });

  final int count;
  final double height;

  /// Слово под числом: «кадра», «кадров» — склонение считает вызывающий.
  final String label;
  final Color? background;
  final Color? foreground;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.secondaryContainer;
    final fg = foreground ?? cs.onSecondaryContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: height * 0.92,
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '+$count',
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontWeight: FontWeight.w800,
                  fontSize: height * 0.26,
                  height: 1,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: height * 0.2,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
