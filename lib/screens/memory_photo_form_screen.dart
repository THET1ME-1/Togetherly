import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../models/memory.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../theme/profile_theme.dart';

import 'map_picker_screen.dart';
import '../services/plus_access.dart';
import '../widgets/app_sheet.dart';
import '../services/plus_service.dart';

/// type авто-определяется: фото → photo, видео → video, без медиа → text.
typedef MemoryPhotoSaveCallback = Future<void> Function({
  required MemoryType type,
  required String title,
  required String caption,
  List<String>? mediaPaths,
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

  const MemoryPhotoFormScreen({
    super.key,
    required this.theme,
    required this.onSave,
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
  void dispose() {
    _titleCtrl.dispose();
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_isSaving &&
      (_media.isNotEmpty ||
          _titleCtrl.text.trim().isNotEmpty ||
          _captionCtrl.text.trim().isNotEmpty);

  // ── Picking photos & video ──────────────────────────────────────────────────

  Future<void> _pickMedia() async {
    try {
      final picked = await ImagePicker().pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;

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
        // Экран собран кадром-героем: фотография занимает верх целиком, а лист
        // с полями наезжает на неё скруглением. Прежняя форма была простынёй,
        // где кадр шёл строкой между полями, и до кнопки приходилось листать
        // всё, даже когда заполнять нечего.
        body: LayoutBuilder(
          builder: (context, box) {
            final heroHeight = box.maxHeight * 0.44;
            final sheetTop = heroHeight - 26;
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: heroHeight + 26,
                  child: _buildHero(cs),
                ),
                Positioned(
                  top: sheetTop,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildSheet(cs, media),
                ),
                Positioned(
                  top: media.padding.top + 6,
                  left: 10,
                  child: _glassButton(
                    cs,
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                if (_media.length > 1)
                  Positioned(
                    top: media.padding.top + 12,
                    right: 16,
                    child: _glassPill(
                      cs,
                      LocaleService.current.itemsShort(_media.length),
                    ),
                  ),
                // Действие всегда на экране и всегда одной ширины: до кнопки в
                // шапке большой палец не дотягивался, а со скроллом она
                // уезжала вместе с формой.
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: media.padding.bottom + 16,
                  child: FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: Text(LocaleService.current.addMemoryToFeed),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      textStyle: const TextStyle(
                        fontFamily: ProfileTheme.bodyFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: isVid
                      ? _videoPreviewWidget(item.path, width: 64, height: 64)
                      : Image.file(File(item.path),
                          width: 64, height: 64, fit: BoxFit.cover),
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

