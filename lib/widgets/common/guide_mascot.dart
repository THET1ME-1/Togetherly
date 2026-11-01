import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';

/// Облачко-гид: анимированный WebP из серверного каталога (вид `art`, ключ
/// `guide_<имя>`). Анимации запекает мастерская значков (`bake_guide.py`),
/// поэтому облачко меняется без новой версии приложения.
///
/// Холст файла с запасом под полёт и предметы вокруг: рисунок облачка
/// занимает около 70% стороны. Пока каталог не загружен или файла нет, место
/// остаётся пустым — раскладка экрана от этого не прыгает.
class GuideMascot extends StatelessWidget {
  const GuideMascot(this.name, {super.key, required this.side});

  /// Имя анимации без приставки: `welcome`, `album`, `girl`, `hint_down`…
  final String name;

  /// Сторона холста на экране, в логических точках.
  final double side;

  @override
  Widget build(BuildContext context) => CatalogArtAnim('guide_$name', side: side);
}

/// До какого размера разжимать анимацию: 240, 480 или 960 пикселей.
///
/// Ступеней три, а не «сколько точек на экране»: заготовка (`warmCatalogArt`)
/// обязана попасть в тот же ключ кэша, что и показ, иначе она бесполезна.
int artDecodeBucket(double px) => px <= 240 ? 240 : (px <= 480 ? 480 : 960);

/// Файл каталога под нужный размер: малый (240) только там, где его не
/// придётся растягивать.
String? catalogArtUrl(String key, int decode, {String? fallbackKey}) => _artUrl(key, decode, fallbackKey: fallbackKey);

String? _artUrl(String key, int decode, {String? fallbackKey}) {
  final catalog = CatalogService.instance;
  final art = catalog.giftArt(key) ?? (fallbackKey == null ? null : catalog.giftArt(fallbackKey));
  return decode > 240 ? (art?.lgUrl ?? art?.smUrl) : (art?.smUrl ?? art?.lgUrl);
}

ImageProvider _artProvider(String url, int decode) => ResizeImage(
      CachedNetworkImageProvider(url, cacheManager: OfflineImageCacheManager.instance),
      width: decode,
      height: decode,
    );

/// Картинка анимации. Смена сцены идёт без затухания и без пустого места:
/// до готовности новой стоит прежний кадр (`gaplessPlayback`). Прежде
/// старая гасла секунду поверх новой, и облачко двоилось.
Image catalogArtImage(String url, {required double side, required int decode}) => Image(
      image: _artProvider(url, decode),
      width: side,
      height: side,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => SizedBox.square(dimension: side),
    );

/// Заранее скачивает и разжимает первые кадры сцен, чтобы смена была
/// мгновенной: касание, другое настроение, другой пол, следующий экран.
/// Анимацию не крутит — после первого кадра отписывается, картинка остаётся
/// в кэше изображений и подхватывается показом сразу.
void warmCatalogArt(Iterable<String> keys, {required double side, double? dpr}) {
  final ratio = dpr ?? ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final decode = artDecodeBucket(side * ratio);
  for (final key in keys) {
    final url = _artUrl(key, decode);
    if (url == null) continue;
    final stream = _artProvider(url, decode).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) => stream.removeListener(listener),
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }
}

/// То же по готовым адресам — для картинок не из `art`, например эмоций пака.
void warmArtUrls(Iterable<String> urls, {required double side, double? dpr}) {
  final ratio = dpr ?? ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final decode = artDecodeBucket(side * ratio);
  for (final url in urls) {
    final stream = _artProvider(url, decode).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) => stream.removeListener(listener),
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }
}

/// Скачивает и разжимает первый кадр сцены; true — кадр готов и показ будет
/// мгновенным, false — в каталоге её нет или файл не дошёл за [timeout].
Future<bool> catalogArtReady(String key, {required double side, required double dpr, Duration timeout = const Duration(seconds: 20)}) {
  final decode = artDecodeBucket(side * dpr);
  final url = _artUrl(key, decode);
  if (url == null) return Future.value(false);
  final done = Completer<bool>();
  final stream = _artProvider(url, decode).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(bool ok) {
    if (done.isCompleted) return;
    stream.removeListener(listener);
    done.complete(ok);
  }

  listener = ImageStreamListener((_, _) => finish(true), onError: (_, _) => finish(false));
  stream.addListener(listener);
  Timer(timeout, () => finish(false));
  return done.future;
}

/// Анимация из каталога (вид `art`) по полному ключу. Общая для гида и для
/// облачка-маскота на главной.
class CatalogArtAnim extends StatelessWidget {
  const CatalogArtAnim(this.artKey, {super.key, required this.side, this.fallbackKey});

  final String artKey;
  final double side;

  /// Что показать, пока нужной анимации в каталоге нет (старый каталог без
  /// цвета настроения): облачко обычного цвета лучше пустоты.
  final String? fallbackKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogService.instance,
      builder: (context, _) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
        final decode = artDecodeBucket(side * dpr);
        final url = _artUrl(artKey, decode, fallbackKey: fallbackKey);
        if (url == null) return SizedBox.square(dimension: side);
        return catalogArtImage(url, side: side, decode: decode);
      },
    );
  }
}
