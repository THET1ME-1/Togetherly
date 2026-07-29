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
import '../widgets/memory_date_field.dart';

import 'map_picker_screen.dart';
import '../services/plus_access.dart';
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

  /// Схема M3 экрана. Форма собрана на ролях (`surfaceContainer`, `primary`,
  /// `outline`), а не на цветах старой темы: зелёная кнопка «На карте» и синяя
  /// «Текущее» были единственными чужими акцентами в фиолетовом приложении.
  ColorScheme get _cs => ProfileTheme.themeFor(widget.theme).colorScheme;

  @override
  Widget build(BuildContext context) {
    final cs = _cs;
    final s = LocaleService.current;

    return Theme(
      data: ProfileTheme.data(cs),
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _buildAppBar(cs, s),
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoPicker(cs.primary),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleField(s),
                    const SizedBox(height: 12),
                    _buildCaptionField(s),
                    const SizedBox(height: 18),
                    _sectionLabel(s.location, cs),
                    const SizedBox(height: 8),
                    _buildLocationSection(cs.primary, s),
                    const SizedBox(height: 18),
                    // Настройки записи — одна карточка: раньше «18+» и «Когда
                    // это было» были двумя блоками с разной геометрией.
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        children: [
                          _buildAdultToggle(s),
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: cs.outlineVariant,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                            child: MemoryDateField(
                              value: _customDate,
                              onChanged: (d) =>
                                  setState(() => _customDate = d),
                              accent: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Основное действие внизу: до кнопки в шапке большой палец не
        // дотягивался, а рядом с крестиком она ещё и путала.
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).padding.bottom + 12,
          ),
          child: FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(s.addMemoryBtn),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) => Text(
        text,
        style: TextStyle(
          fontFamily: ProfileTheme.displayFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      );

  PreferredSizeWidget _buildAppBar(ColorScheme cs, AppStrings s) {
    return AppBar(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded, size: 22),
      ),
      title: Text(
        LocaleService.current.newEntry,
        style: TextStyle(
          fontFamily: ProfileTheme.displayFont,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      ),
      centerTitle: true,
    );
  }

  // ── Media picker ────────────────────────────────────────────────────────────

  Widget _buildPhotoPicker(Color primary) {
    if (_media.isEmpty) return _buildEmptyMediaPicker(primary);
    return _buildFilledMedia(primary);
  }

  // Пустое состояние — вся область = пикер
  Widget _buildEmptyMediaPicker(Color primary) {
    return GestureDetector(
      onTap: _pickMedia,
      child: Container(
        width: double.infinity,
        height: 180,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        decoration: BoxDecoration(
          color: widget.theme.surfaceMuted,
          borderRadius: BorderRadius.circular(18),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: primary.withValues(alpha: 0.35)),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_photo_alternate_rounded,
                      size: 30, color: primary),
                ),
                const SizedBox(height: 8),
                Text(
                  LocaleService.current.photoVideo,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: primary),
                ),
                const SizedBox(height: 3),
                Text(
                  LocaleService.current.optionalTapToSelect,
                  style: TextStyle(fontSize: 12, color: widget.theme.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Заполненное состояние — превью первого элемента + лента миниатюр
  Widget _buildFilledMedia(Color primary) {
    final first = _media.first;
    final isFirstVideo = _isVideo(first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero — первый элемент
        SizedBox(
          width: double.infinity,
          height: 260,
          child: ClipRect(
            child: Stack(
              children: [
                // Превью — Positioned.fill гарантирует обрезку, а не сжатие
                if (isFirstVideo)
                  Positioned.fill(
                    child: _videoPreviewWidget(first.path, fit: BoxFit.cover),
                  )
                else
                  Positioned.fill(
                    child: Image.file(File(first.path), fit: BoxFit.cover),
                  ),
                // Иконка Play для видео
                if (isFirstVideo)
                  const Center(
                    child: Icon(Icons.play_circle_filled_rounded,
                        color: Colors.white, size: 52),
                  ),
                // Счётчик
                if (_media.length > 1)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        LocaleService.current.itemsShort(_media.length),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Лента миниатюр
        const SizedBox(height: 6),
        SizedBox(
          height: 72,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _media.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              // Кнопка "Добавить ещё" в конце
              if (i == _media.length) {
                return GestureDetector(
                  onTap: _pickMedia,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: widget.theme.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: primary.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: Icon(Icons.add_rounded, color: primary, size: 24),
                  ),
                );
              }
              final item = _media[i];
              final isVid = _isVideo(item);
              return Stack(
                children: [
                  // Миниатюра
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: isVid
                        ? _videoPreviewWidget(item.path,
                            width: 72, height: 72)
                        : Image.file(File(item.path),
                            width: 72, height: 72, fit: BoxFit.cover),
                  ),
                  // Play-иконка на видео
                  if (isVid)
                    const Positioned.fill(
                      child: Center(
                        child: Icon(Icons.play_circle_filled_rounded,
                            color: Colors.white70, size: 22),
                      ),
                    ),
                  // Удалить
                  Positioned(
                    top: 3,
                    right: 3,
                    child: GestureDetector(
                      onTap: () => setState(() => _media.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 12),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
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

  /// Поля с меткой, а не с подсказкой внутри: заполненное поле с одним
  /// `hintText` теряло название, и было не понять, где заголовок, а где
  /// описание.
  InputDecoration _fieldDeco(String label, {String? helper}) {
    final cs = _cs;
    return InputDecoration(
      labelText: label,
      helperText: helper,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  Widget _buildTitleField(AppStrings s) {
    return TextField(
      controller: _titleCtrl,
      onChanged: (_) => setState(() {}),
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      decoration: _fieldDeco(s.titleOptional, helper: s.titleFieldHint),
    );
  }

  Widget _buildCaptionField(AppStrings s) {
    return TextField(
      controller: _captionCtrl,
      onChanged: (_) => setState(() {}),
      maxLines: 5,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: _fieldDeco(s.descriptionOptional),
    );
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Widget _buildLocationSection(Color primary, AppStrings s) {
    final cs = _cs;
    // Выбранное место — чип с адресом: одно нажатие ставит, одно снимает.
    if (_lat != null && _lng != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          avatar: Icon(Icons.location_on_rounded,
              size: 18, color: cs.onSecondaryContainer),
          label: Text(
            _locationCtrl.text.isNotEmpty
                ? _locationCtrl.text
                : '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: cs.secondaryContainer,
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSecondaryContainer,
          ),
          onDeleted: _clearLocation,
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
        ),
      );
    }
    // Две равные кнопки одной формы: раньше «Текущее» было синим, «На карте» —
    // зелёным, и оба цвета не имели отношения к теме пары.
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _isLoadingLocation ? null : _useCurrentLocation,
            icon: _isLoadingLocation
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.onSecondaryContainer),
                  )
                : const Icon(Icons.my_location_rounded, size: 19),
            label: Text(s.useCurrent, maxLines: 1),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickOnMap,
            icon: const Icon(Icons.map_rounded, size: 19),
            label: Text(s.pickOnMap, maxLines: 1),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Adult toggle ────────────────────────────────────────────────────────────

  Widget _buildAdultToggle(AppStrings s) {
    final cs = _cs;
    return SwitchListTile(
      value: _isAdult,
      onChanged: (v) => setState(() => _isAdult = v),
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      secondary: Icon(
        _isAdult ? Icons.lock_rounded : Icons.lock_open_rounded,
        size: 22,
        color: _isAdult ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(
        s.adultContent,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        s.photoBlurred,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
    );
  }

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

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashLen = 8.0;
    const gapLen = 5.0;
    const radius = Radius.circular(18);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height), radius));
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
