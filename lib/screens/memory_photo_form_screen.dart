import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../utils/lost_pick.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../models/memory.dart';
import '../services/locale_service.dart';
import '../utils/photo_crop.dart';
import '../utils/safe_pick.dart';
import '../theme/app_theme.dart';
import '../theme/fonts.dart';
import '../widgets/memory/media_strip.dart';
import '../theme/profile_theme.dart';

import 'map_picker_screen.dart';
import '../services/plus_access.dart';
import '../widgets/app_sheet.dart';
import '../services/plus_service.dart';

/// Что подставить в экран записи при правке готовой записи.
class MemoryFormPrefill {
  const MemoryFormPrefill({
    required this.frames,
    this.title = '',
    this.caption = '',
    this.locationName = '',
    this.latitude,
    this.longitude,
    this.isAdult = false,
    this.date,
  });

  /// Кадры записи в порядке показа; первый — обложка.
  final List<String> frames;
  final String title;
  final String caption;
  final String locationName;
  final double? latitude;
  final double? longitude;
  final bool isAdult;
  final DateTime? date;
}

/// type авто-определяется: фото → photo, видео → video, без медиа → text.
typedef MemoryPhotoSaveCallback = Future<void> Function({
  required MemoryType type,
  required String title,
  required String caption,
  List<String>? mediaPaths,
  /// Кадры записи, которые остались после правки, в порядке показа.
  /// Первый из них — обложка. Пусто у новой записи.
  List<String>? keptUrls,
  String? mediaPath,
  String? locationName,
  double? latitude,
  double? longitude,
  required bool isAdult,
  DateTime? customDate,
});

/// Full-page photo memory creation form.
class MemoryPhotoFormScreen extends StatefulWidget {
  final AppTheme theme;
  final MemoryPhotoSaveCallback onSave;

  /// Снимки, уцелевшие после того, как систему убила процесс во время выбора.
  /// Проходят тот же путь, что и выбранные вручную: потолок файла, координаты
  /// из EXIF, миниатюры видео.
  final List<XFile> initialMedia;

  /// Правка готовой записи: те же поля и те же кадры, экран один и тот же.
  final MemoryFormPrefill? existing;

  const MemoryPhotoFormScreen({
    super.key,
    required this.theme,
    required this.onSave,
    this.existing,
    this.initialMedia = const [],
  });

  @override
  State<MemoryPhotoFormScreen> createState() => _MemoryPhotoFormScreenState();
}

class _MemoryPhotoFormScreenState extends State<MemoryPhotoFormScreen> {
  final _titleCtrl = TextEditingController();
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  // Единый список: фото и видео вместе
  List<XFile> _media = [];

  /// Кадры, которые уже лежат в записи. При правке они стоят в плёнке рядом
  /// с только что выбранными, и порядок между ними общий.
  List<String> _kept = [];
  // Кэш превью для видео: path → thumbnail bytes
  final Map<String, Uint8List> _videoThumbs = {};

  double? _lat;
  double? _lng;
  bool _isAdult = false;
  bool _isSaving = false;
  bool _isLoadingLocation = false;
  DateTime? _customDate;

  static bool _isVideo(XFile f) {
    final ext = f.path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext);
  }

  // Авто-определяемый тип: есть фото → photo, только видео → video, пусто → text
  MemoryType get _effectiveType {
    if (_media.isEmpty) return MemoryType.text;
    final hasPhoto = _media.any((f) => !_isVideo(f));
    if (hasPhoto) return MemoryType.photo;
    return MemoryType.video;
  }

  @override
  void initState() {
    super.initState();
    final pre = widget.existing;
    if (pre != null) {
      _titleCtrl.text = pre.title;
      _captionCtrl.text = pre.caption;
      _locationCtrl.text = pre.locationName;
      _lat = pre.latitude;
      _lng = pre.longitude;
      _isAdult = pre.isAdult;
      _customDate = pre.date;
      _kept = [...pre.frames];
    }
    // Снимки, пережившие смерть процесса во время выбора: человек их уже
    // выбрал, заставлять его повторять — значит потерять их второй раз.
    if (widget.initialMedia.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _acceptPicked(widget.initialMedia),
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  bool get _hasFrames => _media.isNotEmpty || _kept.isNotEmpty;

  /// Что писать поверх заливки темы: правило одно на всё приложение.
  Color get _onFill =>
      AppThemes.onColor(widget.theme.fillColor, mode: widget.theme.brightness);

  bool get _canSave =>
      !_isSaving &&
      (_hasFrames ||
          _titleCtrl.text.trim().isNotEmpty ||
          _captionCtrl.text.trim().isNotEmpty);

  // ── Picking photos & video ──────────────────────────────────────────────────

  Future<void> _pickMedia() async {
    try {
      final picked = await safePick(
        () => ImagePicker().pickMultipleMedia(),
        intent: kPickIntentMemory,
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      await _acceptPicked(picked);
    } catch (e) {
      _showError(LocaleService.current.failedSelectPhotos(e.toString()));
    }
  }

  /// Приём пачки файлов в форму: и от галереи, и от восстановления.
  Future<void> _acceptPicked(List<XFile> picked) async {
    try {
      // Потолок файла: 100 МБ обычно, 200 с Togetherly+. Проверяем ДО добавления
      // в форму — иначе тяжёлое видео уходило бы в очередь и висело там, получая
      // отказ сервера уже без человека у экрана.
      final plus = PlusService.instance.active;
      final tooBig = <XFile>[];
      final fits = <XFile>[];
      for (final f in picked) {
        final size = await File(f.path).length();
        (PlusAccess.fitsMemoryLimit(bytes: size, plus: plus) ? fits : tooBig)
            .add(f);
      }
      if (!mounted) return;
      if (tooBig.isNotEmpty) {
        final limitMb = PlusAccess.memoryFileLimit(plus: plus) ~/ (1024 * 1024);
        // Про больший потолок рассказываем только там, где Togetherly+ можно
        // купить. На iOS его не существует — там просто потолок.
        final hintsPlus = !plus && PlusService.instance.visible;
        _showError(hintsPlus
            ? LocaleService.current.memoryFileTooBigPlusHint(limitMb)
            : LocaleService.current.memoryFileTooBig(limitMb));
      }
      if (fits.isEmpty) return;
      picked
        ..clear()
        ..addAll(fits);
      setState(() => _media = [..._media, ...picked]);
      if (_lat == null) {
        final firstPhoto =
            picked.firstWhere((f) => !_isVideo(f), orElse: () => picked.first);
        if (!_isVideo(firstPhoto)) _tryExifGps(firstPhoto.path);
      }
      for (final f in picked) {
        if (_isVideo(f) && !_videoThumbs.containsKey(f.path)) {
          _generateVideoThumb(f.path);
        }
      }
    } catch (e) {
      _showError(LocaleService.current.failedSelectPhotos(e.toString()));
    }
  }

  /// Кадрирование уже выбранного снимка. Пачку кроппером не гоняем: человек
  /// выбирает сразу несколько кадров, и открывать редактор на каждый — пытка.
  /// Поэтому обрезка идёт по требованию: тап по плитке или кнопка на кадре.
  ///
  /// Координаты снимка к этому моменту уже прочитаны (`_tryExifGps` при
  /// выборе), а кроппер EXIF не сохраняет — иначе метка места пропадала бы
  /// у каждого обрезанного фото.
  Future<void> _cropAt(int index) async {
    if (index < 0 || index >= _media.length) return;
    final item = _media[index];
    if (_isVideo(item)) return;
    final path = await cropPhoto(item.path, accentColor: _cs.primary);
    if (path == null || !mounted) return;
    setState(() => _media[index] = XFile(path));
  }

  Future<void> _generateVideoThumb(String path) async {
    try {
      final thumb = await VideoCompress.getByteThumbnail(
        path,
        quality: 60,
        position: -1,
      );
      if (thumb != null && mounted) {
        setState(() => _videoThumbs[path] = thumb);
      }
    } catch (_) {}
  }

  Future<void> _tryExifGps(String path) async {
    final coords = await _extractExifGps(path);
    if (coords == null || !mounted) return;
    final addr = await _reverseGeocode(coords.$1, coords.$2);
    if (!mounted) return;
    setState(() {
      _lat = coords.$1;
      _lng = coords.$2;
      _locationCtrl.text = addr;
    });
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showError(LocaleService.current.locationServicesDisabled);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showError(LocaleService.current.locationPermissionDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final addr = await _reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationCtrl.text = addr;
      });
    } catch (_) {
      _showError(LocaleService.current.failedGetLocation);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MapPickerScreen(initialLatitude: _lat, initialLongitude: _lng),
        settings: const RouteSettings(name: '/map_picker'),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result['latitude'] as double?;
        _lng = result['longitude'] as double?;
        _locationCtrl.text = result['address'] as String? ?? '';
      });
    }
  }

  void _clearLocation() => setState(() {
        _lat = null;
        _lng = null;
        _locationCtrl.clear();
      });

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    Navigator.pop(context);
    final photos = _media.where((f) => !_isVideo(f)).toList();
    final videos = _media.where((f) => _isVideo(f)).toList();
    await widget.onSave(
      type: _effectiveType,
      title: _titleCtrl.text.trim(),
      caption: _captionCtrl.text.trim(),
      mediaPaths: photos.isNotEmpty ? photos.map((f) => f.path).toList() : null,
      keptUrls: _kept.isEmpty ? null : List<String>.from(_kept),
      mediaPath: videos.isNotEmpty ? videos.first.path : null,
      locationName: _locationCtrl.text.trim().isEmpty
          ? null
          : _locationCtrl.text.trim(),
      latitude: _lat,
      longitude: _lng,
      isAdult: _isAdult,
      customDate: _customDate,
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade400),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  /// Схема M3 экрана: цвета берём ролями, а не из старой темы.
  ColorScheme get _cs => ProfileTheme.themeFor(widget.theme).colorScheme;

  /// Выбранное место человеку видно строкой чипа.
  bool get _hasPlace => _lat != null && _lng != null;

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final media = MediaQuery.of(context);

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        // Экран записи один на всё: под новую запись он открывается пустым,
        // из готовой — карандашом в шапке пина. Кадры не обрезаются: обложка
        // стоит целиком, в своей пропорции, остальные идут плёнкой под ней.
        body: Column(
          children: [
            SizedBox(height: media.padding.top + 8),
            _formBar(cs),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _formMedia(cs),
                    const SizedBox(height: 10),
                    _formHint(cs),
                    const SizedBox(height: 12),
                    _formFields(cs),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                // Галерея и камера — смежной парой, как у кнопки сохранения.
                Row(children: [
                  _formRound(cs,
                      icon: Icons.add_photo_alternate_rounded,
                      onTap: _pickMedia,
                      radius: const BorderRadius.horizontal(
                          left: Radius.circular(32), right: Radius.circular(10))),
                  const SizedBox(width: 2),
                  _formRound(cs,
                      icon: Icons.photo_camera_rounded,
                      onTap: _pickFromCamera,
                      radius: const BorderRadius.horizontal(
                          left: Radius.circular(10), right: Radius.circular(32))),
                ]),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.check_rounded, size: 22),
                    label: Text(LocaleService.current.save),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      textStyle: const TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Круглая кнопка: 48 в шапке, 64 в нижней паре — как в макете.
  Widget _formRound(ColorScheme cs,
      {required IconData icon,
      required VoidCallback onTap,
      BorderRadius? radius,
      double size = 64}) {
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: radius ?? BorderRadius.circular(size / 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size > 56 ? 26 : 22, color: cs.onSurface),
        ),
      ),
    );
  }

  /// Шапка: крестик, сводка по записи и «ещё». Названия экрана нет — и так
  /// видно, что открыто; место занимает то, что правда полезно.
  Widget _formBar(ColorScheme cs) {
    // Считаем и прежние кадры записи, и только что выбранные.
    final total = _kept.length + _media.length;
    final label = total == 0
        ? LocaleService.current.newMemoryDraft
        : '${LocaleService.current.newMemoryDraft} · '
            '$total ${LocaleService.current.photosUnit(total)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(
        children: [
          _formRound(cs,
              icon: Icons.close_rounded,
              size: 48,
              onTap: () => Navigator.pop(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: widget.theme.fillColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.onest(
                          size: 13.5, weight: 700, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Обложка целиком и плёнка кадров: плитка с плюсом стоит ПЕРВОЙ, иначе
  /// при прокрутке она уезжает за край и добавить кадр нечем.
  Widget _formMedia(ColorScheme cs) {
    if (!_hasFrames) {
      return GestureDetector(
        onTap: _pickMedia,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_rounded,
                  size: 34, color: cs.primary),
              const SizedBox(height: 8),
              Text(LocaleService.current.addPhotoOrVideo,
                  style: AppFonts.onest(
                      size: 15, weight: 600, color: cs.onSurface)),
            ],
          ),
        ),
      );
    }
    // Кадры записи идут одним рядом: сперва прежние (при правке), затем
    // только что выбранные. Обложка — первый в этом ряду.
    final keptCount = _kept.length;
    final total = keptCount + _media.length;
    Widget frameAt(int i, double height, {bool cover = false}) {
      if (i < keptCount) {
        final url = _kept[i];
        return cover
            ? AspectCover(url: url, radius: 22, maxHeight: 400)
            : FilmFrame(
                url: url,
                height: height,
                onTap: () => _makeCover(i),
                onLongPress: () => _removeAt(i),
              );
      }
      final file = _media[i - keptCount];
      if (_isVideo(file)) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(cover ? 22 : 8),
          child: cover
              ? AspectRatio(
                  aspectRatio: 4 / 3, child: _videoPreviewWidget(file.path))
              : GestureDetector(
                  onTap: () => _makeCover(i),
                  onLongPress: () => _removeAt(i),
                  child: SizedBox(
                      width: 92,
                      height: height,
                      child: _videoPreviewWidget(file.path)),
                ),
        );
      }
      return cover
          ? AspectCover(
              url: file.path,
              provider: FileImage(File(file.path)),
              radius: 22,
              maxHeight: 400,
            )
          : FilmFrame(
              url: file.path,
              provider: FileImage(File(file.path)),
              height: height,
              onTap: () => _makeCover(i),
              onLongPress: () => _removeAt(i),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            frameAt(0, 0, cover: true),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                height: 30,
                padding: const EdgeInsets.only(left: 9, right: 12),
                decoration: BoxDecoration(
                  color: widget.theme.fillColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 16, color: _onFill),
                    const SizedBox(width: 5),
                    Text(LocaleService.current.coverLabel,
                        style: AppFonts.onest(
                            size: 12.5, weight: 700, color: _onFill)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Material(
                color: cs.inverseSurface,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _removeAt(0),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.close_rounded,
                        size: 20, color: cs.onInverseSurface),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: total,
            separatorBuilder: (_, _) => const SizedBox(width: 2),
            itemBuilder: (_, i) {
              // Плитка с плюсом стоит ПЕРВОЙ: в конце ряда она уезжает за
              // край, и добавить кадр становится нечем.
              if (i == 0) {
                return Material(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _pickMedia,
                    child: SizedBox(
                      width: 92,
                      height: 132,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              size: 28, color: cs.onSecondaryContainer),
                          const SizedBox(height: 4),
                          Text(LocaleService.current.addLabel,
                              style: AppFonts.onest(
                                  size: 11.5,
                                  weight: 700,
                                  color: cs.onSecondaryContainer)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return frameAt(i, 132);
            },
          ),
        ),
      ],
    );
  }

  /// Поставить кадр обложкой: он уходит в начало ряда, прежний сдвигается.
  void _makeCover(int index) {
    setState(() {
      if (index < _kept.length) {
        final x = _kept.removeAt(index);
        _kept.insert(0, x);
      } else {
        final i = index - _kept.length;
        final x = _media.removeAt(i);
        if (_kept.isEmpty) {
          _media.insert(0, x);
        } else {
          // Новый кадр становится обложкой только вместе с переездом в
          // начало общего ряда: прежние кадры уступают ему место.
          _media.insert(0, x);
          _kept = [];
          _media = [x, ..._media.where((f) => f != x)];
        }
      }
    });
  }

  /// Подсказка под плёнкой: что делают касание и долгое нажатие.
  Widget _formHint(ColorScheme cs) {
    if (_media.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              LocaleService.current.formFramesHint,
              style: AppFonts.onest(
                  size: 13, weight: 500, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  /// Поля записи одной группой, как в настройках: смежные блоки с круглым
  /// чипом-иконкой. Название и подпись выделены — это главное у записи.
  Widget _formFields(ColorScheme cs) {
    final dateLabel = _customDate == null
        ? LocaleService.current.dateNowLabel
        : _formatCustomDate(_customDate!);
    return Column(
      children: [
        _formRow(cs,
            icon: Icons.title_rounded,
            label: LocaleService.current.titleOptional,
            value: _titleCtrl.text,
            placeholder: LocaleService.current.titleHintForm,
            key0: true,
            first: true,
            onTap: () => _editText(_titleCtrl, LocaleService.current.titleOptional)),
        const SizedBox(height: 4),
        _formRow(cs,
            icon: Icons.edit_note_rounded,
            label: LocaleService.current.descriptionOptional,
            value: _captionCtrl.text,
            placeholder: LocaleService.current.captionHintForm,
            key0: true,
            onTap: () => _editText(
                _captionCtrl, LocaleService.current.descriptionOptional,
                lines: 5)),
        const SizedBox(height: 4),
        _formRow(cs,
            icon: Icons.calendar_today_rounded,
            label: LocaleService.current.memoryDateLabelForm,
            value: dateLabel,
            chevron: true,
            onTap: _pickCustomDate),
        const SizedBox(height: 4),
        _formRow(cs,
            icon: Icons.place_rounded,
            label: LocaleService.current.placeLabelForm,
            value: _locationCtrl.text.isEmpty
                ? LocaleService.current.placeHintForm
                : _locationCtrl.text,
            chevron: true,
            onTap: _showPlaceSheet),
        const SizedBox(height: 4),
        _formRow(cs,
            icon: Icons.visibility_off_rounded,
            label: LocaleService.current.adultContent,
            value: _isAdult
                ? LocaleService.current.onLabel
                : LocaleService.current.offLabel,
            last: true,
            toggle: _isAdult,
            onTap: () => setState(() => _isAdult = !_isAdult)),
      ],
    );
  }

  /// Строка формы: круглый чип, подпись сверху, значение под ней.
  Widget _formRow(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
    String? placeholder,
    bool key0 = false,
    bool first = false,
    bool last = false,
    bool chevron = false,
    bool? toggle,
    required VoidCallback onTap,
  }) {
    final empty = value.trim().isEmpty;
    final text = empty ? (placeholder ?? '') : value;
    final bg = key0 ? cs.secondaryContainer : cs.surfaceContainerHigh;
    final fg = key0 ? cs.onSecondaryContainer : cs.onSurface;
    final sub = key0
        ? cs.onSecondaryContainer.withValues(alpha: 0.8)
        : cs.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(first ? 28 : 8),
        bottom: Radius.circular(last ? 28 : 8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: key0 ? widget.theme.fillColor : cs.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 22, color: key0 ? _onFill : cs.onSurface),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppFonts.onest(
                            size: 12.5, weight: 600, color: sub)),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.onest(
                        size: key0 ? 17 : 16,
                        weight: empty ? 500 : (key0 ? 700 : 600),
                        color: empty ? sub : fg,
                      ),
                    ),
                  ],
                ),
              ),
              if (toggle != null)
                Switch(
                  value: toggle,
                  onChanged: (_) => onTap(),
                )
              else if (chevron)
                Icon(Icons.chevron_right_rounded, color: sub),
            ],
          ),
        ),
      ),
    );
  }

  /// Правка текстового поля отдельным листом — так строка остаётся строкой,
  /// а клавиатура не ломает раскладку экрана.
  Future<void> _editText(TextEditingController ctrl, String title,
      {int lines = 1}) async {
    final value = await showAppSheet<String>(
      context,
      builder: (ctx) => SheetScaffold(
        title: title,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _TextSheetBody(
            initial: ctrl.text,
            lines: lines,
            onDone: (v) => Navigator.pop(ctx, v),
          ),
        ),
      ),
    );
    if (value != null) setState(() => ctrl.text = value);
  }

  /// Убрать кадр из записи — по общему ряду: сперва прежние, затем новые.
  void _removeAt(int index) {
    setState(() {
      if (index < _kept.length) {
        _kept.removeAt(index);
        return;
      }
      final i = index - _kept.length;
      if (i >= 0 && i < _media.length) _media.removeAt(i);
    });
  }

  /// Снять кадр камерой и положить в запись.
  Future<void> _pickFromCamera() async {
    final shot = await safePick(
      () => ImagePicker().pickImage(source: ImageSource.camera),
      intent: kPickIntentMemory,
    );
    if (shot != null) await _acceptPicked([shot]);
  }

  // ── Кадр ───────────────────────────────────────────────────────────────────

  Widget _buildHero(ColorScheme cs) {
    if (_media.isEmpty) {
      // Пустой кадр зовёт сам собой: тональная плоскость во всю ширину вместо
      // прямоугольника с пунктиром — обводок на экране нет вовсе.
      return GestureDetector(
        onTap: _pickMedia,
        child: Container(
          color: cs.surfaceContainerHigh,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.add_photo_alternate_rounded,
                    size: 34, color: cs.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                LocaleService.current.photoVideo,
                style: TextStyle(
                  fontFamily: ProfileTheme.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleService.current.optionalTapToSelect,
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final first = _media.first;
    final isFirstVideo = _isVideo(first);
    return GestureDetector(
      onTap: _pickMedia,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isFirstVideo)
            _videoPreviewWidget(first.path, fit: BoxFit.cover)
          else
            Image.file(File(first.path), fit: BoxFit.cover),
          if (isFirstVideo)
            const Center(
              child: Icon(Icons.play_circle_filled_rounded,
                  color: Colors.white, size: 56),
            ),
        ],
      ),
    );
  }

  /// Кружок поверх фотографии. Полупрозрачная подложка нужна, чтобы крестик
  /// читался и на светлом кадре, и на тёмном.
  Widget _glassButton(ColorScheme cs,
      {required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: cs.inverseSurface.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 22, color: cs.onInverseSurface),
        ),
      ),
    );
  }

  Widget _glassPill(ColorScheme cs, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.inverseSurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onInverseSurface,
        ),
      ),
    );
  }

  // ── Лист с полями ─────────────────────────────────────────────────────────

  Widget _buildSheet(ColorScheme cs, MediaQueryData media) {
    final s = LocaleService.current;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                media.padding.bottom + 96,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_media.isNotEmpty) ...[
                    _buildThumbRow(cs),
                    // Про обрезку иначе не догадаются: тап по миниатюре
                    // выглядит как выбор, а не как вход в редактор.
                    if (_media.any((m) => !_isVideo(m))) ...[
                      const SizedBox(height: 6),
                      Text(
                        LocaleService.current.cropPhotoHint,
                        style: TextStyle(
                          fontFamily: ProfileTheme.bodyFont,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                  _buildTitleField(s),
                  const SizedBox(height: 10),
                  _buildCaptionField(s),
                  const SizedBox(height: 14),
                  _buildMetaChips(cs, s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Лента миниатюр. Плитка добавления — такая же по форме и размеру, как
  /// кадры: ряд читается лентой, а не «две картинки и дырка с плюсом».
  Widget _buildThumbRow(ColorScheme cs) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _media.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == _media.length) {
            return Material(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickMedia,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.photo_library_rounded,
                      size: 24, color: cs.onPrimaryContainer),
                ),
              ),
            );
          }
          final item = _media[i];
          final isVid = _isVideo(item);
          return SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: isVid ? null : () => _cropAt(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: isVid
                        ? _videoPreviewWidget(item.path, width: 64, height: 64)
                        : Image.file(File(item.path),
                            key: ValueKey(item.path),
                            width: 64, height: 64, fit: BoxFit.cover),
                  ),
                ),
                if (isVid)
                  const Positioned.fill(
                    child: Center(
                      child: Icon(Icons.play_circle_filled_rounded,
                          color: Colors.white70, size: 22),
                    ),
                  ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: () => setState(() => _media.removeAt(i)),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: cs.inverseSurface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close_rounded,
                          size: 14, color: cs.onInverseSurface),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Метки: место, дата, 18+ ───────────────────────────────────────────────

  /// Три чипа вместо двух блоков формы. Пустой зовёт, заполненный показывает
  /// значение и снимается крестиком — экран из-за них больше не растёт.
  Widget _buildMetaChips(ColorScheme cs, AppStrings s) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _metaChip(
          cs: cs,
          icon: Icons.location_on_rounded,
          label: _hasPlace
              ? (_locationCtrl.text.isNotEmpty
                  ? _locationCtrl.text
                  : '${_lat!.toStringAsFixed(3)}, ${_lng!.toStringAsFixed(3)}')
              : s.location,
          filled: _hasPlace,
          accent: true,
          loading: _isLoadingLocation,
          onTap: _showPlaceSheet,
          onClear: _hasPlace ? _clearLocation : null,
        ),
        _metaChip(
          cs: cs,
          icon: Icons.schedule_rounded,
          label: _customDate == null
              ? s.dateNowLabel
              : _formatCustomDate(_customDate!),
          filled: _customDate != null,
          onTap: _pickCustomDate,
          onClear: _customDate == null
              ? null
              : () => setState(() => _customDate = null),
        ),
        _metaChip(
          cs: cs,
          icon: _isAdult ? Icons.lock_rounded : Icons.lock_open_rounded,
          label: s.adultContent,
          filled: _isAdult,
          onTap: () => setState(() => _isAdult = !_isAdult),
        ),
      ],
    );
  }

  Widget _metaChip({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
    bool accent = false,
    bool loading = false,
    VoidCallback? onClear,
  }) {
    final bg = !filled
        ? cs.surfaceContainerHigh
        : (accent ? cs.primaryContainer : cs.secondaryContainer);
    final fg = !filled
        ? cs.onSurface
        : (accent ? cs.onPrimaryContainer : cs.onSecondaryContainer);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 9, onClear == null ? 15 : 8, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(icon, size: 18, color: fg),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded, size: 16, color: fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Лист выбора места. Обе кнопки — роли схемы: зелёная «На карте» была
  /// единственным зелёным пятном в теме пары.
  void _showPlaceSheet() {
    final cs = _cs;
    final s = LocaleService.current;
    showAppSheet<void>(
      context,
      background: cs.surfaceContainer,
      builder: (ctx) => Theme(
        data: ProfileTheme.data(cs),
        child: SheetScaffold(
          title: s.location,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _placeRow(
                  cs: cs,
                  icon: Icons.my_location_rounded,
                  title: s.useCurrent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _useCurrentLocation();
                  },
                ),
                const SizedBox(height: 10),
                _placeRow(
                  cs: cs,
                  icon: Icons.map_rounded,
                  title: s.pickOnMap,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickOnMap();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeRow({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 22, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Дата и время записи — стандартные пикеры M3 вместо самодельной пары
  /// кнопок «Дата / Время».
  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final base = _customDate ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: now,
      builder: (ctx, child) => Theme(data: ProfileTheme.data(_cs), child: child!),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => Theme(data: ProfileTheme.data(_cs), child: child!),
    );
    if (!mounted) return;
    setState(() {
      _customDate = DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? base.hour,
        time?.minute ?? base.minute,
      );
    });
  }

  String _formatCustomDate(DateTime d) {
    final months = LocaleService.current.shortMonths;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hh:$mm';
  }

  // ── Поля ──────────────────────────────────────────────────────────────────

  /// Поля стоят на заливке, без единой линии: подпись отличается от описания
  /// плотностью фона и весом текста.
  InputDecoration _fieldDeco(String label, {Color? fill}) {
    final cs = _cs;
    final shape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      floatingLabelStyle: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: fill ?? cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: shape,
      enabledBorder: shape,
      focusedBorder: shape,
    );
  }

  Widget _buildTitleField(AppStrings s) {
    return TextField(
      controller: _titleCtrl,
      onChanged: (_) => setState(() {}),
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      decoration: _fieldDeco(s.titleOptional),
    );
  }

  Widget _buildCaptionField(AppStrings s) {
    return TextField(
      controller: _captionCtrl,
      onChanged: (_) => setState(() {}),
      maxLines: 4,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      decoration: _fieldDeco(
        s.descriptionOptional,
        fill: _cs.surfaceContainer,
      ),
    );
  }

  // Виджет превью видео: показывает кэшированный thumb или тёмный фон
  Widget _videoPreviewWidget(String path,
      {BoxFit fit = BoxFit.cover, double? width, double? height}) {
    final thumb = _videoThumbs[path];
    if (thumb != null) {
      return Image.memory(thumb,
          fit: fit,
          width: width,
          height: height ?? double.infinity);
    }
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade800,
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              color: Colors.white70, strokeWidth: 2),
        ),
      ),
    );
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<(double, double)?> _extractExifGps(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final tags = await readExifFromBytes(bytes);
      if (!tags.containsKey('GPS GPSLatitude') ||
          !tags.containsKey('GPS GPSLongitude')) {
        return null;
      }
      final latRef =
          tags['GPS GPSLatitudeRef']?.printable.trim() ?? 'N';
      final lngRef =
          tags['GPS GPSLongitudeRef']?.printable.trim() ?? 'E';
      double? toDeg(String raw) {
        final clean = raw.replaceAll(RegExp(r'[\[\]\s]'), '');
        final parts = clean.split(',');
        if (parts.length < 3) return null;
        double p(String s) {
          if (s.contains('/')) {
            final f = s.split('/');
            final n = double.tryParse(f[0]);
            final d = double.tryParse(f[1]);
            if (n == null || d == null || d == 0) return 0;
            return n / d;
          }
          return double.tryParse(s) ?? 0;
        }
        return p(parts[0]) + p(parts[1]) / 60.0 + p(parts[2]) / 3600.0;
      }

      final latVal = toDeg(tags['GPS GPSLatitude']!.printable);
      final lngVal = toDeg(tags['GPS GPSLongitude']!.printable);
      if (latVal == null ||
          lngVal == null ||
          (latVal == 0.0 && lngVal == 0.0)) {
        return null;
      }
      return (
        latRef == 'S' ? -latVal : latVal,
        lngRef == 'W' ? -lngVal : lngVal
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final ps = await placemarkFromCoordinates(lat, lng);
      if (ps.isNotEmpty) {
        final place = ps.first;
        final name = place.name ?? place.subLocality ?? '';
        final locality = place.locality ?? '';
        return name.isNotEmpty ? '$name, $locality' : locality;
      }
    } catch (_) {}
    return '';
  }
}

// ── Dashed border painter ────────────────────────────────────────────────────

/// Правка одной строки записи в нижнем листе: поле и кнопка «Готово».
///
/// Отдельным листом, а не полем прямо в форме: клавиатура иначе поднимает
/// экран целиком и плёнка кадров уезжает за край.
class _TextSheetBody extends StatefulWidget {
  const _TextSheetBody({
    required this.initial,
    required this.lines,
    required this.onDone,
  });

  final String initial;
  final int lines;
  final ValueChanged<String> onDone;

  @override
  State<_TextSheetBody> createState() => _TextSheetBodyState();
}

class _TextSheetBodyState extends State<_TextSheetBody> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          minLines: widget.lines,
          maxLines: widget.lines + 2,
          style: AppFonts.onest(size: 16, weight: 500, color: cs.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: cs.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => widget.onDone(_ctrl.text.trim()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          child: Text(LocaleService.current.done),
        ),
      ],
    );
  }
}
