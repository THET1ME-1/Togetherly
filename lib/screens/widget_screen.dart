import 'dart:io';
import 'dart:ui';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pair_data.dart';
import '../models/timer_item.dart';
import '../models/widget_data.dart';
import '../models/user_data.dart';
import '../models/mood_entry.dart';
import '../models/memory.dart';
import '../services/firebase_service.dart';
import '../services/home_widget_service.dart';
import '../services/locale_service.dart';
import '../services/mood_service.dart';
import '../services/timer_service.dart';
import '../services/widget_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common/m3_loading.dart';

/// Экран виджетов — два тайла (мой / партнёра) + настройки автоотправки.
class WidgetScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final WidgetService widgetService;
  final MoodService moodService;
  final TimerService timerService;
  final AppTheme theme;

  const WidgetScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.widgetService,
    required this.moodService,
    required this.timerService,
    required this.theme,
  });

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  AppTheme get _t => widget.theme;
  WidgetService get _ws => widget.widgetService;
  MoodService get _moodService => widget.moodService;
  TimerService get _timerService => widget.timerService;
  PairData get _pair => widget.pairData;
  AppStrings get _s => LocaleService.current;

  bool _canPinWidgets = false;
  bool _pairWidgetExpanded = false;
  bool _timerWidgetExpanded = false;
  String? _widgetTimerId;

  int? _memoriesCount;
  int? _drawingsCount;
  int? _missYouCount;

  // Фото дня
  bool _photoDayExpanded = true;
  String _photoDayMode = 'random'; // 'random' | 'custom'
  bool _savePhotoAsMemory = true;
  String? _myOwnPhotoPath; // МОЁ фото (показывается в превью по умолчанию)
  String?
  _partnerWidgetPhotoPath; // Фото партнёра (всегда отображается на рабочем столе)
  bool _previewShowsPartner = false; // Переключатель превью: моё ↔ партнёра
  int _photoDayVersion = 0;
  bool _isLoadingPhoto = false;

  String get _widgetTimerKey => 'widget_timer_id_${_pair.pairId}';

  static const String _heartSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="m11.645 20.91-.007-.003-.022-.012a15.247 15.247 0 0 1-.383-.218 25.18 25.18 0 0 1-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0 1 12 5.052 5.5 5.5 0 0 1 16.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 0 1-4.244 3.17 15.247 15.247 0 0 1-.383.219l-.022.012-.007.004-.003.001a.752.752 0 0 1-.704 0l-.003-.001Z" /></svg>''';
  static const String _calendarSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M6.75 2.25A.75.75 0 0 1 7.5 3v1.5h9V3A.75.75 0 0 1 18 3v1.5h.75a3 3 0 0 1 3 3v11.25a3 3 0 0 1-3 3H5.25a3 3 0 0 1-3-3V7.5a3 3 0 0 1 3-3H6V3a.75.75 0 0 1 .75-.75Zm13.5 9a1.5 1.5 0 0 0-1.5-1.5H5.25a1.5 1.5 0 0 0-1.5 1.5v7.5a1.5 1.5 0 0 0 1.5 1.5h13.5a1.5 1.5 0 0 0 1.5-1.5v-7.5Z" clip-rule="evenodd" /></svg>''';
  static const String _timerSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25ZM12.75 6a.75.75 0 0 0-1.5 0v6c0 .414.336.75.75.75h4.5a.75.75 0 0 0 0-1.5h-3.75V6Z" clip-rule="evenodd" /></svg>''';
  static const String _photoSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M1.5 6a2.25 2.25 0 0 1 2.25-2.25h16.5A2.25 2.25 0 0 1 22.5 6v12a2.25 2.25 0 0 1-2.25 2.25H3.75A2.25 2.25 0 0 1 1.5 18V6ZM3 16.06V18c0 .414.336.75.75.75h16.5A.75.75 0 0 0 21 18v-1.94l-2.69-2.689a1.5 1.5 0 0 0-2.12 0l-.88.879.97.97a.75.75 0 1 1-1.06 1.06l-5.16-5.159a1.5 1.5 0 0 0-2.12 0L3 16.061Zm10.125-7.81a1.125 1.125 0 1 1 2.25 0 1.125 1.125 0 0 1-2.25 0Z" clip-rule="evenodd" /></svg>''';
  static const String _moodSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25Zm-2.625 6c-.54 0-.828.419-.936.634a1.96 1.96 0 0 0-.189.866c0 .298.059.605.189.866.108.215.395.634.936.634.54 0 .828-.419.936-.634.13-.26.189-.568.189-.866 0-.298-.059-.605-.189-.866-.108-.215-.395-.634-.936-.634Zm4.314.634c.108-.215.395-.634.936-.634.54 0 .828.419.936.634.13.26.189.568.189.866 0 .298-.059.605-.189.866-.108.215-.395.634-.936.634-.54 0-.828-.419-.936-.634a1.96 1.96 0 0 1-.189-.866c0-.298.059-.605.189-.866Zm-4.34 7.964a.75.75 0 0 1-1.061-1.06 5.236 5.236 0 0 1 3.73-1.538 5.236 5.236 0 0 1 3.695 1.538.75.75 0 1 1-1.061 1.06 3.736 3.736 0 0 0-2.639-1.098 3.736 3.736 0 0 0-2.664 1.098Z" clip-rule="evenodd" /></svg>''';
  static const String _statsSvg =
      '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M3 6a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V6Zm4.5 7.5a.75.75 0 0 1 .75.75v2.25a.75.75 0 0 1-1.5 0v-2.25a.75.75 0 0 1 .75-.75Zm3.75-1.5a.75.75 0 0 0-1.5 0v4.5a.75.75 0 0 0 1.5 0V12Zm2.25-3a.75.75 0 0 1 .75.75v6.75a.75.75 0 0 1-1.5 0V9.75A.75.75 0 0 1 13.5 9Zm3.75-1.5a.75.75 0 0 0-1.5 0v9a.75.75 0 0 0 1.5 0v-9Z" clip-rule="evenodd" /></svg>''';

  // Геттер: выбранный таймер для виджета (non-system)
  TimerItem? get _widgetTimer {
    final nonSystem = _timerService.timers.where((t) => !t.isSystem).toList();
    if (nonSystem.isEmpty) return null;
    if (_widgetTimerId != null) {
      try {
        return nonSystem.firstWhere((t) => t.id == _widgetTimerId);
      } catch (_) {}
    }
    return nonSystem.first;
  }

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onDataChanged);
    _timerService.addListener(_onDataChanged);
    _moodService.addListener(_onDataChanged);
    _checkPinSupport();
    _loadWidgetTimerId();
    _loadStats();
    _loadPhotoDayPrefs();
    // Подписываемся на настроение партнёров
    for (final p in _pair.partners) {
      _moodService.listenToPartner(p.uid);
    }
  }

  void _loadStats() {
    final groupId = _pair.pairId;
    if (groupId.isEmpty) return;

    // Load memories count
    FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('memories')
        .count()
        .get()
        .then((snap) {
          if (mounted) setState(() => _memoriesCount = snap.count ?? 0);
        })
        .catchError((_) {});

    // Load drawings count
    FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('canvases')
        .count()
        .get()
        .then((snap) {
          if (mounted) setState(() => _drawingsCount = snap.count ?? 0);
        })
        .catchError((_) {});

    // Miss you (from group doc)
    FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .listen((snap) {
          if (snap.exists && mounted) {
            setState(() => _missYouCount = snap.data()?['missYouCount'] ?? 0);
          }
        });
  }

  Future<void> _loadWidgetTimerId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_widgetTimerKey);
    if (mounted) setState(() => _widgetTimerId = id);
  }

  Future<void> _loadPhotoDayPrefs() async {
    final hws = HomeWidgetService.instance;
    final mode = await hws.getPhotoDayMode(_pair.pairId);
    final save = await hws.getPhotoDaySaveMemory(_pair.pairId);
    final prefs = await SharedPreferences.getInstance();

    // Моё фото: для custom-режима — мой выбранный файл
    final customPath = prefs.getString('photo_day_path_${_pair.pairId}');

    // Фото на рабочем столе (ВСЕГДА фото партнёра или случайное)
    final widgetPath = await HomeWidget.getWidgetData<String>('photo_day_path');

    // Определяем МОЁ фото для превью
    String? myPhoto;
    if (mode == 'custom') {
      // В кастомном режиме показываем мой выбранный файл
      if (customPath != null &&
          customPath.isNotEmpty &&
          File(customPath).existsSync()) {
        myPhoto = customPath;
      } else {
        // Fallback: URL из Firestore (если файл удалён/устарел)
        myPhoto = (_ws.myData?.photoUrl?.isNotEmpty == true)
            ? _ws.myData!.photoUrl
            : null;
      }
    } else {
      // В random-режиме превью показывает то же, что на рабочем столе
      // (случайное фото или фото партнёра в режиме random+custom)
      myPhoto = (widgetPath != null && widgetPath.isNotEmpty)
          ? widgetPath
          : null;
    }

    if (mounted) {
      setState(() {
        _photoDayMode = mode;
        _savePhotoAsMemory = save;
        _myOwnPhotoPath = myPhoto;
        _partnerWidgetPhotoPath = (widgetPath != null && widgetPath.isNotEmpty)
            ? widgetPath
            : null;
        _photoDayVersion++;
      });
    }
  }

  Future<void> _selectPhotoDayMode(String mode) async {
    final hws = HomeWidgetService.instance;
    // Если уже в этом режиме и это random — генерируем следующее фото
    final forceNext = mode == 'random' && _photoDayMode == 'random';
    // Сохраняем режим локально и в Firestore
    await hws.setPhotoDayMode(_pair.pairId, mode);
    await _ws.setPhotoDayMode(mode);
    setState(() {
      _photoDayMode = mode;
      _isLoadingPhoto = true;
      _previewShowsPartner = false; // сбрасываем переключатель превью
    });
    // Виджет рабочего стола ВСЕГДА показывает фото партнёра
    // refreshPhotoOfDay сам определит правильное фото по матрице режимов
    await hws.refreshPhotoOfDay(_pair.pairId, forceNext: forceNext);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _loadPhotoDayPrefs();
    if (mounted) setState(() => _isLoadingPhoto = false);
  }

  Future<void> _toggleSavePhotoAsMemory(bool value) async {
    final hws = HomeWidgetService.instance;
    await hws.setPhotoDaySaveMemory(_pair.pairId, value);
    setState(() => _savePhotoAsMemory = value);
  }

  Future<void> _pickCustomPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile == null) return;

    final file = File(pickedFile.path);
    final hws = HomeWidgetService.instance;
    final fb = FirebaseService();
    final prefs = await SharedPreferences.getInstance();

    // 1. Загружаем фото один раз и публикуем в widgetData
    //    Используем updatePhotoUrl (без auto-save в Memory Lane), чтобы
    //    избежать дублирования — запись в Memory Lane управляется только
    //    флагом _savePhotoAsMemory ниже.
    String? uploadedUrl;
    try {
      if (_savePhotoAsMemory) {
        // Загружаем в папку memories/, чтобы партнёр мог скачать то же фото
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final destination = 'memories/${_pair.pairId}/photo_day_$timestamp.jpg';
        uploadedUrl = await fb.uploadFile(file.path, destination);
        if (uploadedUrl != null) {
          await fb.addMemory(
            groupId: _pair.pairId,
            type: MemoryType.photo,
            imageUrl: uploadedUrl,
            caption: LocaleService.instance.isRussian
                ? 'Установлено как фото дня'
                : 'Set as Photo of the Day',
          );
          _loadStats();
        }
      } else {
        // Загружаем в папку widget/ без создания записи в Memory Lane
        final uid = fb.uid ?? '';
        final ts = DateTime.now().millisecondsSinceEpoch;
        uploadedUrl = await fb.uploadFile(
          file.path,
          'widget/${_pair.pairId}/${uid}_$ts.jpg',
        );
      }
    } catch (e) {
      debugPrint('Failed to upload photo day: $e');
    }

    // 2. Публикуем URL в widgetData (партнёр увидит как «custom»)
    await _ws.setPhotoDayMode('custom');
    if (uploadedUrl != null) {
      await _ws.updatePhotoUrl(uploadedUrl);
    }

    // 3. Сохраняем путь к локальному файлу (для превью в приложении)
    await prefs.setString('photo_day_path_${_pair.pairId}', file.path);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (mounted) setState(() => _myOwnPhotoPath = file.path);

    // 4. Обновляем виджет рабочего стола (показывает фото ПАРТНЁРА)
    await hws.refreshPhotoOfDay(_pair.pairId);
    await _loadPhotoDayPrefs();
  }

  Future<void> _selectWidgetTimer(TimerItem timer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_widgetTimerKey, timer.id);
    setState(() => _widgetTimerId = timer.id);
    await HomeWidgetService.instance.syncTimer(timer);
  }

  Future<void> _checkPinSupport() async {
    if (!Platform.isAndroid) return;
    // requestPinWidget supported on Android 8.0+ (API 26+) on most launchers.
    // Some launchers return false even though pinning works — show button anyway.
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (mounted)
        setState(() => _canPinWidgets = (supported ?? false) || true);
    } catch (e) {
      // Fallback: show button on Android regardless
      if (mounted) setState(() => _canPinWidgets = true);
    }
  }

  Future<void> _pinWidget(String qualifiedName, {String? widgetType}) async {
    debugPrint(
      '_pinWidget called: qualifiedName=$qualifiedName, widgetType=$widgetType',
    );
    try {
      final className = qualifiedName.split('.').last;
      debugPrint('_pinWidget: requesting pin for className=$className');
      await HomeWidget.requestPinWidget(
        name: className,
        androidName: className,
      );
      debugPrint('_pinWidget: requestPinWidget completed successfully');
      // Привязываем виджет к текущей группе и СРАЗУ синхронизируем данные
      if (widgetType != null && _pair.pairId.isNotEmpty) {
        await HomeWidgetService.instance.bindWidgetToGroup(
          widgetType,
          _pair.pairId,
        );
        // Немедленно записать актуальные данные в виджет
        await _syncWidgetDataAfterPin(widgetType);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LocaleService.instance.isRussian
                  ? 'Виджет добавлен на рабочий стол'
                  : 'Widget added to home screen',
            ),
            backgroundColor: Colors.green.shade400,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Pin widget failed: $e');
      debugPrint('Pin widget stack: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LocaleService.instance.isRussian
                  ? 'Не удалось добавить виджет: $e'
                  : 'Failed to add widget: $e',
            ),
            backgroundColor: Colors.red.shade400,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Сразу после пина записывает данные текущей группы в виджет.
  Future<void> _syncWidgetDataAfterPin(String widgetType) async {
    final hws = HomeWidgetService.instance;
    switch (widgetType) {
      case 'days_counter':
        final sysTimer = _timerService.systemTimer;
        final start = sysTimer?.startDate ?? _pair.startDate;
        final emoji = sysTimer?.emoji ?? _pair.relationshipEmoji;
        final days = sysTimer != null
            ? sysTimer.daysElapsed.abs()
            : (start != null ? DateTime.now().difference(start).inDays : 0);
        final startLabel = start != null
            ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
            : '';
        final names = _pair.partnerName.isNotEmpty ? _pair.partnerName : '';
        await hws.syncDaysCounter(
          daysCount: days,
          coupleNames: names,
          emoji: emoji,
          startDate: startLabel,
        );
        break;
      case 'timer':
        final timer = _widgetTimer;
        if (timer != null) await hws.syncTimer(timer);
        break;
      case 'photo_day':
        await hws.refreshPhotoOfDay(_pair.pairId);
        break;
      case 'pair':
        // Парный виджет синхронизируется WidgetService
        break;
      case 'mood':
        // Синхронизируем из Mood Calendar за сегодня
        {
          final today = DateTime.now();
          final myEntries = _moodService.myEntriesForDay(today);
          final myEntry = myEntries.isNotEmpty ? myEntries.first : null;
          final partnerUid = _pair.partners.isNotEmpty
              ? _pair.partners.first.uid
              : '';
          final partnerEntries = partnerUid.isNotEmpty
              ? _moodService.partnerEntriesForDay(partnerUid, today)
              : <MoodEntry>[];
          final partnerEntry = partnerEntries.isNotEmpty
              ? partnerEntries.first
              : null;
          await hws.syncMood(
            moodEmojiAssetPath: myEntry?.imagePath ?? '',
            moodLabel: myEntry?.label ?? '',
            userName: _ws.myData?.displayName ?? '',
            partnerMoodEmojiAssetPath: partnerEntry?.imagePath ?? '',
            partnerMoodLabel: partnerEntry?.label ?? '',
            partnerUserName: _pair.partnerName,
          );
        }
        break;
      case 'relationship_stats':
        final sysTimer = _timerService.systemTimer;
        final start = sysTimer?.startDate ?? _pair.startDate;
        final isRu = LocaleService.instance.isRussian;
        await hws.syncRelationshipStats(
          daysTogether: start != null
              ? DateTime.now().difference(start).inDays
              : 0,
          memoriesCount: _memoriesCount ?? 0,
          drawingsCount: _drawingsCount ?? 0,
          missYouCount: _missYouCount ?? 0,
          daysLabel: isRu ? 'Дней вместе' : 'Days Together',
          memoriesLabel: isRu ? 'Воспоминаний' : 'Memories',
          drawingsLabel: isRu ? 'Рисунков' : 'Drawings',
          missYouLabel: isRu ? 'Скучаю' : 'Miss Yous',
        );
        break;
    }
  }

  @override
  void didUpdateWidget(WidgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pairData.pairId != widget.pairData.pairId) {
      // Сменилась группа — загружаем выбор таймера для новой группы
      _loadWidgetTimerId();
      _loadPhotoDayPrefs();
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onDataChanged);
    _timerService.removeListener(_onDataChanged);
    _moodService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (!_pair.isPaired) return _buildNotPaired();

    return Stack(
      fit: StackFit.expand,
      children: [
        _t.bgImageUrl != null
            ? CachedNetworkImage(
                imageUrl: _t.bgImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _t.bgGradient,
                  ),
                ),
              ),
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                  child: Column(
                    children: [
                      // ── Галерея виджетов рабочего стола ──
                      _buildWidgetGallery(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.widgets_rounded, color: _t.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            _s.widgetsTitle,
            style: GoogleFonts.rubik(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const Spacer(),
          // Кнопка «Очистить мой виджет»
          if (_ws.myData != null && !_ws.myData!.isEmpty)
            GestureDetector(
              onTap: _confirmClearAll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear_all_rounded,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _s.resetBtn,
                      style: GoogleFonts.rubik(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade400,
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

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET PREVIEW (как выглядит на рабочем столе)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildWidgetPreview() {
    final my = _ws.myData ?? WidgetData(uid: '');
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                _s.desktopPreview,
                style: GoogleFonts.rubik(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                _t.heroGradient[0],
                _t.heroGradient.length > 1
                    ? _t.heroGradient[1]
                    : _t.heroGradient[0],
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _t.heroShadowBase.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // ── Левая половина: Я ──
                    Expanded(
                      child: _buildPreviewHalf(
                        data: my,
                        label: _s.me,
                        isLeft: true,
                      ),
                    ),
                    // ── Разделитель ──
                    Container(
                      width: 1,
                      height: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0),
                            Colors.white.withOpacity(0.5),
                            Colors.white.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                    // ── Правая половина: Партнёр ──
                    Expanded(
                      child: _buildPreviewHalf(
                        data: partner,
                        label: _pair.partnerName.isNotEmpty
                            ? _pair.partnerName
                            : _s.partner,
                        isLeft: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewHalf({
    required WidgetData data,
    required String label,
    required bool isLeft,
  }) {
    return Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        // Имя
        Text(
          label,
          style: GoogleFonts.rubik(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white.withOpacity(0.7),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        // Emoji
        if (data.hasMood)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(data.moodEmoji, width: 20, height: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  data.moodLabel,
                  style: GoogleFonts.rubik(fontSize: 10, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          Text(
            '—',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        const SizedBox(height: 4),
        // Статус
        Text(
          data.hasStatus ? data.status : _s.noStatus,
          style: GoogleFonts.rubik(
            fontSize: 10,
            fontWeight: data.hasStatus ? FontWeight.w600 : FontWeight.w400,
            color: Colors.white.withOpacity(data.hasStatus ? 0.95 : 0.35),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        // Сообщение
        if (data.hasMessage)
          Text(
            '«${data.message}»',
            style: GoogleFonts.rubik(
              fontSize: 9,
              fontStyle: FontStyle.italic,
              color: Colors.white.withOpacity(0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        // Музыка
        if (data.hasMusic)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 10,
                  color: Colors.white.withOpacity(0.6),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    '${data.musicTitle}',
                    style: GoogleFonts.rubik(
                      fontSize: 9,
                      color: Colors.white.withOpacity(0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // WIDGET GALLERY — все виджеты с превью и кнопкой «Добавить»
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildWidgetGallery() {
    final isRu = LocaleService.instance.isRussian;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                Icons.dashboard_customize_rounded,
                size: 16,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                isRu ? 'Виджеты рабочего стола' : 'Home Screen Widgets',
                style: GoogleFonts.rubik(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),

        // ── 1. Парный виджет ──
        _buildGalleryItem(
          title: isRu ? 'Парный виджет' : 'Pair Widget',
          subtitle: isRu
              ? 'Настроение, статус, сообщения и фото'
              : 'Mood, status, messages & photos',
          svgString: _heartSvg,
          qualifiedName: 'com.example.love_app.LoveWidgetProvider',
          preview: _buildWidgetPreview(),
          widgetType: 'pair',
          expandedContent: _buildPairWidgetExpandedContent(),
          isExpanded: _pairWidgetExpanded,
          onToggleExpand: () =>
              setState(() => _pairWidgetExpanded = !_pairWidgetExpanded),
        ),
        const SizedBox(height: 16),

        // ── 2. Счётчик дней вместе ──
        _buildGalleryItem(
          title: isRu ? 'Дни вместе' : 'Days Together',
          subtitle: isRu
              ? 'Системный счётчик дней отношений'
              : 'Relationship day counter',
          svgString: _calendarSvg,
          qualifiedName: 'com.example.love_app.DaysCounterWidgetProvider',
          preview: _buildDaysCounterPreview(),
          widgetType: 'days_counter',
        ),
        const SizedBox(height: 16),

        // ── 3. Таймер ──
        _buildGalleryItem(
          title: isRu ? 'Таймер' : 'Timer',
          subtitle: isRu
              ? 'Выберите таймер для виджета'
              : 'Choose a timer for the widget',
          svgString: _timerSvg,
          qualifiedName: 'com.example.love_app.TimerWidgetProvider',
          preview: _buildTimerPreview(),
          widgetType: 'timer',
          expandedContent: _buildTimerSelector(),
          isExpanded: _timerWidgetExpanded,
          onToggleExpand: () =>
              setState(() => _timerWidgetExpanded = !_timerWidgetExpanded),
        ),
        const SizedBox(height: 16),

        // ── 4. Фото дня ──
        _buildGalleryItem(
          title: isRu ? 'Фото дня' : 'Photo of the Day',
          subtitle: isRu
              ? (_photoDayMode == 'random'
                    ? 'Случайное фото из ленты'
                    : 'Своё установленное фото')
              : (_photoDayMode == 'random'
                    ? 'Random photo from Memory Lane'
                    : 'Custom set photo'),
          svgString: _photoSvg,
          qualifiedName: 'com.example.love_app.PhotoDayWidgetProvider',
          preview: _buildPhotoDayPreview(),
          widgetType: 'photo_day',
          expandedContent: _buildPhotoDayExpandedContent(),
          isExpanded: _photoDayExpanded,
          onToggleExpand: () =>
              setState(() => _photoDayExpanded = !_photoDayExpanded),
        ),
        const SizedBox(height: 16),

        // ── 5. Настроение ──
        _buildGalleryItem(
          title: isRu ? 'Настроение' : 'Mood',
          subtitle: isRu
              ? 'Горизонтальный виджет: моё и партнёра'
              : 'Horizontal widget: mine & partner\'s',
          svgString: _moodSvg,
          qualifiedName: 'com.example.love_app.MoodWidgetProvider',
          preview: _buildMoodPreview(),
          widgetType: 'mood',
        ),
        const SizedBox(height: 16),

        // ── 6. Статистика отношений ──
        _buildGalleryItem(
          title: isRu ? 'Статистика отношений' : 'Relationship Stats',
          subtitle: isRu
              ? 'Важные цифры: дни, фото, рисунки и «скучаю»'
              : 'Important stats: days, photos, drawings & miss yous',
          svgString: _statsSvg,
          qualifiedName: 'com.example.love_app.RelationshipStatsWidgetProvider',
          preview: _buildRelationshipStatsPreview(),
          widgetType: 'relationship_stats',
        ),
      ],
    );
  }

  Widget _buildGalleryItem({
    required String title,
    required String subtitle,
    required String svgString,
    required String qualifiedName,
    required Widget preview,
    String? widgetType,
    Widget? expandedContent,
    bool isExpanded = false,
    VoidCallback? onToggleExpand,
  }) {
    final isRu = LocaleService.instance.isRussian;
    final iconColor = _t.primary;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Заголовок ──
          GestureDetector(
            onTap: onToggleExpand,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.string(
                      svgString,
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.rubik(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.rubik(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onToggleExpand != null)
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Превью виджета ──
          preview,
          // ── Кнопка «Добавить на рабочий стол» ──
          if (_canPinWidgets) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _pinWidget(qualifiedName, widgetType: widgetType),
                icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                label: Text(
                  isRu ? 'Добавить на рабочий стол' : 'Add to Home Screen',
                  style: GoogleFonts.rubik(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _t.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
          // ── Раскрываемое содержимое ──
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: expandedContent != null && isExpanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Divider(color: Colors.grey.shade200, height: 1),
                      const SizedBox(height: 16),
                      expandedContent,
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Счётчик дней
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildDaysCounterPreview() {
    final isRu = LocaleService.instance.isRussian;
    // Данные берём ИЗ системного таймера (isSystem == true)
    final sysTimer = _timerService.systemTimer;
    final start = sysTimer?.startDate ?? _pair.startDate;
    final totalDays = sysTimer != null
        ? sysTimer.daysElapsed.abs()
        : (start != null ? DateTime.now().difference(start).inDays : 0);
    final startLabel = start != null
        ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
        : '';

    final myGender = widget.userData.gender?.name ?? 'male';
    final partnerGender = _ws.firstPartnerData?.gender.isNotEmpty == true
        ? _ws.firstPartnerData!.gender
        : 'female';

    String imgName = 'widget_couple_mf';
    if (myGender == 'female' && partnerGender == 'female') {
      imgName = 'widget_couple_ff';
    } else if (myGender == 'male' && partnerGender == 'male') {
      imgName = 'widget_couple_mm';
    }

    final years = totalDays ~/ 365;
    String yearsText;
    if (years % 10 == 1 && years % 100 != 11) {
      yearsText = '$years год уже ❤️';
    } else if (years % 10 >= 2 &&
        years % 10 <= 4 &&
        (years % 100 < 10 || years % 100 >= 20)) {
      yearsText = '$years года уже ❤️';
    } else {
      yearsText = '$years лет уже ❤️';
    }

    if (!isRu) {
      yearsText = '$years years already ❤️';
    }

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: _t.cardSurface,
        border: Border.all(color: _t.primary.withOpacity(0.15), width: 3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(21),
              ),
              child: Image.asset(
                'assets/images/widget/$imgName.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                yearsText,
                style: GoogleFonts.rubik(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _t.primary.withOpacity(0.7),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$totalDays',
                  style: GoogleFonts.rubik(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: _t.primary,
                    height: 1.0,
                  ),
                ),
                Text(
                  isRu ? 'дней' : 'Days',
                  style: GoogleFonts.rubik(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _t.primary.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  startLabel,
                  style: GoogleFonts.rubik(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _t.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Таймер
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimerPreview() {
    final timer = _widgetTimer;
    final isRu = LocaleService.instance.isRussian;

    if (timer == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: _t.primary.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _t.primary.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.timer_off_rounded,
              size: 36,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              isRu ? 'Нет таймеров' : 'No timers',
              style: GoogleFonts.rubik(
                fontSize: 13,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isRu
                  ? 'Добавьте таймер в разделе «Таймеры»'
                  : 'Add a timer in the Timers section',
              style: GoogleFonts.rubik(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final title = timer.title;
    final emoji = timer.emoji;
    final days = timer.daysElapsed.abs();
    final isCountdown = timer.isCountdown;
    final daysLabel = isCountdown
        ? (isRu ? 'дней осталось' : 'days left')
        : (isRu ? 'дней прошло' : 'days elapsed');
    final date = timer.formattedStartDate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_t.primary.withOpacity(0.06), _t.primary.withOpacity(0.12)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _t.primary.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.rubik(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$days',
            style: GoogleFonts.rubik(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: _t.primary,
              height: 1.1,
            ),
          ),
          Text(
            daysLabel,
            style: GoogleFonts.rubik(fontSize: 14, color: Colors.grey.shade500),
          ),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              date,
              style: GoogleFonts.rubik(
                fontSize: 10,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВЫБОР ТАЙМЕРА ДЛЯ ВИДЖЕТА
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildTimerSelector() {
    final isRu = LocaleService.instance.isRussian;
    final nonSystem = _timerService.timers.where((t) => !t.isSystem).toList();

    if (nonSystem.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          isRu
              ? 'Нет таймеров. Добавьте таймер в разделе «Таймеры».'
              : 'No timers. Add a timer in the Timers section.',
          style: GoogleFonts.rubik(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRu ? 'Выберите таймер для виджета:' : 'Select timer for widget:',
          style: GoogleFonts.rubik(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 10),
        ...nonSystem.map((timer) {
          final isSelected = timer.id == (_widgetTimerId ?? nonSystem.first.id);
          return GestureDetector(
            onTap: () => _selectWidgetTimer(timer),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF8B5CF6).withOpacity(0.1)
                    : Colors.grey.shade50,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF8B5CF6)
                      : Colors.grey.shade200,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(timer.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timer.title,
                          style: GoogleFonts.rubik(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? _t.primary
                                : _t.primary.withOpacity(0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${timer.daysElapsed.abs()} '
                          '${timer.isCountdown ? (isRu ? 'дн. осталось' : 'd. left') : (isRu ? 'дн. прошло' : 'd. elapsed')} • ${timer.formattedStartDate}',
                          style: GoogleFonts.rubik(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Фото дня
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoDayPreview() {
    final isRu = LocaleService.instance.isRussian;

    // Определяем какое фото показывать в превью
    final displayPath = _previewShowsPartner
        ? _partnerWidgetPhotoPath
        : _myOwnPhotoPath;

    // Превью-заголовок для пустого состояния
    final emptyLabel = _previewShowsPartner
        ? (isRu
              ? 'Фото партнёра появится\nпосле его выбора'
              : 'Partner\'s photo will appear\nafter they choose one')
        : (_photoDayMode == 'custom'
              ? (isRu ? 'Выберите фото \u043dиже' : 'Choose a photo below')
              : (isRu
                    ? 'Случайное фото\nиз воспоминаний'
                    : 'Random photo\nfrom memories'));

    return Column(
      children: [
        // Переключатель: Моё фото ↔ Фото на виджете
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _previewShowsPartner = false),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: !_previewShowsPartner
                          ? _t.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(10),
                      ),
                      border: Border.all(
                        color: !_previewShowsPartner
                            ? _t.primary
                            : _t.cardBorder,
                        width: !_previewShowsPartner ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 14,
                          color: !_previewShowsPartner
                              ? _t.primary
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isRu ? 'Моё' : 'Mine',
                          style: GoogleFonts.rubik(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: !_previewShowsPartner
                                ? _t.primary
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _previewShowsPartner = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: _previewShowsPartner
                          ? _t.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(10),
                      ),
                      border: Border.all(
                        color: _previewShowsPartner
                            ? _t.primary
                            : _t.cardBorder,
                        width: _previewShowsPartner ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.phone_android_rounded,
                          size: 14,
                          color: _previewShowsPartner
                              ? _t.primary
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isRu ? 'На виджете' : 'On widget',
                          style: GoogleFonts.rubik(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _previewShowsPartner
                                ? _t.primary
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Превью фото
        AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _t.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _t.primary.withOpacity(0.1)),
            ),
            child: Stack(
              children: [
                if (displayPath != null && displayPath.isNotEmpty)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: displayPath.startsWith('http')
                          ? Image.network(
                              displayPath,
                              fit: BoxFit.cover,
                              key: ValueKey(
                                'net_${displayPath}_${_photoDayVersion}',
                              ),
                            )
                          : Image.file(
                              File(displayPath),
                              fit: BoxFit.cover,
                              key: ValueKey(
                                'file_${displayPath}_${_photoDayVersion}',
                              ),
                            ),
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _previewShowsPartner ? '👥' : '📷',
                          style: const TextStyle(fontSize: 36),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          emptyLabel,
                          style: GoogleFonts.rubik(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _t.primary.withOpacity(0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                if (_isLoadingPhoto)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          color: Colors.white.withOpacity(0.35),
                          child: Center(
                            child: _MD3PhotoLoader(color: _t.primary),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // НАСТРОЙКИ ФОТО ДНЯ
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPhotoDayExpandedContent() {
    final isRu = LocaleService.instance.isRussian;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRu ? 'Источник фото:' : 'Photo source:',
          style: GoogleFonts.rubik(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _t.primary.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildModeButton(
                label: isRu ? 'Случайное' : 'Random',
                icon: Icons.shuffle_rounded,
                isSelected: _photoDayMode == 'random',
                showRefresh: _photoDayMode == 'random',
                subtitle: isRu ? 'из воспоминаний' : 'from memories',
                onTap: () => _selectPhotoDayMode('random'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModeButton(
                label: isRu ? 'Своё фото' : 'Own Photo',
                icon: Icons.image_rounded,
                isSelected: _photoDayMode == 'custom',
                subtitle: isRu ? 'из галереи' : 'from gallery',
                onTap: () => _selectPhotoDayMode('custom'),
              ),
            ),
          ],
        ),
        if (_photoDayMode == 'custom') ...[
          const SizedBox(height: 16),
          _buildGlassCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickCustomPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, size: 16),
                        label: Text(
                          isRu ? 'Галерея' : 'Gallery',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _t.primaryLight,
                          foregroundColor: _t.primary,
                          elevation: 0,
                          textStyle: const TextStyle(fontSize: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickCustomPhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_rounded, size: 16),
                        label: Text(
                          isRu ? 'Камера' : 'Camera',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _t.primaryLight,
                          foregroundColor: _t.primary,
                          elevation: 0,
                          textStyle: const TextStyle(fontSize: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isRu
                            ? 'Добавить в ленту воспоминаний'
                            : 'Save to Memory Lane',
                        style: GoogleFonts.rubik(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: _savePhotoAsMemory,
                      activeColor: _t.primary,
                      onChanged: _toggleSavePhotoAsMemory,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? subtitle,
    bool showRefresh = false,
  }) {
    final isRu = LocaleService.instance.isRussian;
    // Подсказка: если активна и есть showRefresh — показываем «Повторная генерация»;
    // иначе — subtitle (нужен чтобы обе кнопки имели одинаковую высоту)
    final String resolvedSubtitle;
    if (isSelected && showRefresh) {
      resolvedSubtitle = isRu ? 'Повторная генерация' : 'Regenerate';
    } else {
      resolvedSubtitle = subtitle ?? '';
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _t.primary.withOpacity(0.08) : _t.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _t.primary : _t.cardBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? _t.primary : Colors.grey.shade400,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.rubik(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? _t.primary : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              resolvedSubtitle,
              style: GoogleFonts.rubik(
                fontSize: 9,
                color: isSelected && showRefresh
                    ? _t.primary.withOpacity(0.6)
                    : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Настроение
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMoodPreview() {
    final isRu = LocaleService.instance.isRussian;
    final today = DateTime.now();

    // Моё настроение из Mood Calendar за сегодня
    final myEntries = _moodService.myEntriesForDay(today);
    final myEntry = myEntries.isNotEmpty ? myEntries.first : null;

    // Настроение партнёра из Mood Calendar за сегодня
    final partnerUid = _pair.partners.isNotEmpty
        ? _pair.partners.first.uid
        : '';
    final partnerEntries = partnerUid.isNotEmpty
        ? _moodService.partnerEntriesForDay(partnerUid, today)
        : <MoodEntry>[];
    final partnerEntry = partnerEntries.isNotEmpty
        ? partnerEntries.first
        : null;

    final myName = _ws.myData?.displayName.isNotEmpty == true
        ? _ws.myData!.displayName
        : (isRu ? 'Я' : 'Me');
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : (isRu ? 'Партнёр' : 'Partner');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_t.primary.withOpacity(0.05), _t.primary.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _t.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          // ── Левая часть: Моё настроение ──
          Expanded(
            child: _buildMoodHalf(
              entry: myEntry,
              name: myName,
              isLeft: true,
              isRu: isRu,
            ),
          ),
          // ── Разделитель ──
          Container(
            width: 1,
            height: 80,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey.shade200.withOpacity(0),
                  Colors.grey.shade300,
                  Colors.grey.shade200.withOpacity(0),
                ],
              ),
            ),
          ),
          // ── Правая часть: Настроение партнёра ──
          Expanded(
            child: _buildMoodHalf(
              entry: partnerEntry,
              name: partnerName,
              isLeft: false,
              isRu: isRu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodHalf({
    required MoodEntry? entry,
    required String name,
    required bool isLeft,
    required bool isRu,
  }) {
    return Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          name,
          style: GoogleFonts.rubik(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500,
            letterSpacing: 0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (entry != null) ...[
          Image.asset(
            entry.imagePath,
            width: 48,
            height: 48,
            errorBuilder: (_, __, ___) =>
                const Text('😶', style: TextStyle(fontSize: 36)),
          ),
          const SizedBox(height: 4),
          Text(
            entry.label,
            style: GoogleFonts.rubik(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _t.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ] else ...[
          const Text('😶', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 4),
          Text(
            isRu ? 'Нет' : 'None',
            style: GoogleFonts.rubik(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ВИДЖЕТ-ПРЕВЬЮ: Статистика отношений
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildRelationshipStatsPreview() {
    final isRu = LocaleService.instance.isRussian;
    final sysTimer = _timerService.systemTimer;
    final start = sysTimer?.startDate ?? _pair.startDate;
    final daysNum = start != null ? DateTime.now().difference(start).inDays : 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _t.cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _t.cardBorder),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSmallStatBox(
                  icon: Icons.calendar_today_rounded,
                  color: _t.iconCalendar,
                  value: '$daysNum',
                  label: isRu ? 'Дней вместе' : 'Days Together',
                  bg: _t.iconCalendar.withOpacity(0.08),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSmallStatBox(
                  icon: Icons.photo_library_rounded,
                  color: _t.iconPost,
                  value: '${_memoriesCount ?? 0}',
                  label: isRu ? 'Воспоминаний' : 'Memories',
                  bg: _t.iconPost.withOpacity(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSmallStatBox(
                  icon: Icons.brush_rounded,
                  color: _t.iconDraw,
                  value: '${_drawingsCount ?? 0}',
                  label: isRu ? 'Рисунков' : 'Drawings',
                  bg: _t.iconDraw.withOpacity(0.08),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSmallStatBox(
                  icon: Icons.favorite_rounded,
                  color: _t.primary,
                  value: '${_missYouCount ?? 0}',
                  label: isRu ? 'Скучаю' : 'Miss Yous',
                  bg: _t.primary.withOpacity(0.08),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStatBox({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.rubik(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.rubik(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PAIR WIDGET — раскрытые настройки
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPairWidgetExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMyTile(),
        const SizedBox(height: 12),
        _buildPartnerTile(),
        const SizedBox(height: 12),
        _buildSettingsSection(),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MY TILE (editable)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildMyTile() {
    final data = _ws.myData ?? WidgetData(uid: '');

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_t.primary, _t.primary.withOpacity(0.7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.myWidget,
                    style: GoogleFonts.rubik(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    _s.tapToEdit,
                    style: GoogleFonts.rubik(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _buildEditBadge(),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты ──
          _buildSlotRow(
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: _s.mood,
            value: data.hasMood ? data.moodLabel : null,
            valueColor: Colors.white,
            trailing: data.hasMood
                ? Image.asset(data.moodEmoji, width: 24, height: 24)
                : null,
            onTap: () => _showMoodPicker(),
            onClear: data.hasMood
                ? () async {
                    final today = DateTime.now();
                    for (final e in _moodService.myEntriesForDay(today)) {
                      await _moodService.deleteMoodEntry(e.id);
                    }
                    _pair.clearMood();
                    _ws.clearMood();
                  }
                : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: data.hasStatus ? data.status : null,
            onTap: () => _showTextEditor(
              title: _s.status,
              hint: _s.statusHint,
              initial: data.status,
              maxLength: 50,
              onSave: (v) => _ws.updateStatus(v),
            ),
            onClear: data.hasStatus ? () => _ws.clearStatus() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.mail_outline_rounded,
            iconColor: _t.primary,
            label: _s.message,
            value: data.hasMessage ? '«${data.message}»' : null,
            onTap: () => _showTextEditor(
              title: _s.message,
              hint: _s.messageHint,
              initial: data.message,
              maxLength: 200,
              onSave: (v) => _ws.updateMessage(v),
            ),
            onClear: data.hasMessage ? () => _ws.clearMessage() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: _s.photo,
            value: data.hasPhoto ? _s.photoUploaded : null,
            trailing: data.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: data.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder:
                          (context, url, downloadProgress) {
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _t.primary,
                                    value: downloadProgress.progress,
                                  ),
                                ),
                              ),
                            );
                          },
                      errorWidget: (context, url, error) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: () => _pickPhoto(),
            onClear: data.hasPhoto ? () => _ws.clearPhoto() : null,
          ),
          _slotDivider(),
          _buildSlotRow(
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: _s.music,
            value: data.hasMusic
                ? '${data.musicTitle} — ${data.musicArtist}'
                : null,
            onTap: () => _showMusicEditor(data),
            onClear: data.hasMusic ? () => _ws.clearMusic() : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PARTNER TILE (read-only)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildPartnerTile() {
    final partner = _ws.firstPartnerData ?? WidgetData(uid: '');
    final partnerName = _pair.partnerName.isNotEmpty
        ? _pair.partnerName
        : _s.partner;

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                  image: _pair.partnerAvatarUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_pair.partnerAvatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _pair.partnerAvatarUrl.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        color: Colors.grey.shade500,
                        size: 22,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s.widgetOfPartner(partnerName),
                    style: GoogleFonts.rubik(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  Text(
                    partner.isEmpty ? _s.emptyYet : _s.updated,
                    style: GoogleFonts.rubik(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!partner.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: GoogleFonts.rubik(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Слоты (read-only) ──
          _buildReadonlySlot(
            icon: Icons.emoji_emotions_outlined,
            iconColor: _t.iconMood,
            label: _s.mood,
            value: partner.hasMood ? partner.moodLabel : null,
            valueColor: Colors.white,
            trailing: partner.hasMood
                ? Image.asset(partner.moodEmoji, width: 24, height: 24)
                : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: _t.primary,
            label: _s.status,
            value: partner.hasStatus ? partner.status : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.mail_outline_rounded,
            iconColor: _t.primary,
            label: _s.message,
            value: partner.hasMessage ? '«${partner.message}»' : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.photo_camera_outlined,
            iconColor: _t.iconPost,
            label: _s.photo,
            value: partner.hasPhoto ? _s.photo : null,
            trailing: partner.hasPhoto
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: partner.photoUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      progressIndicatorBuilder:
                          (context, url, downloadProgress) {
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _t.primary,
                                    value: downloadProgress.progress,
                                  ),
                                ),
                              ),
                            );
                          },
                      errorWidget: (context, url, error) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.broken_image_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          _slotDivider(),
          _buildReadonlySlot(
            icon: Icons.music_note_rounded,
            iconColor: _t.iconCalendar,
            label: _s.music,
            value: partner.hasMusic
                ? '${partner.musicTitle} — ${partner.musicArtist}'
                : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SETTINGS SECTION
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                _s.widgetSettings,
                style: GoogleFonts.rubik(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
        _buildGlassCard(
          child: Column(
            children: [
              _buildSettingToggle(
                icon: Icons.photo_library_outlined,
                iconColor: _t.iconPost,
                title: _s.photoToMemoryLane,
                subtitle: _s.autoSavePhotoToMemories,
                value: _ws.autoSendPhotoToMemory,
                onChanged: (v) => _ws.setAutoSendPhotoToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.chat_outlined,
                iconColor: _t.primary,
                title: _s.messagestoMemoryLane,
                subtitle: _s.autoSaveMessages,
                value: _ws.autoSendMessageToMemory,
                onChanged: (v) => _ws.setAutoSendMessageToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.music_note_outlined,
                iconColor: _t.iconCalendar,
                title: _s.musicToMemoryLane,
                subtitle: _s.autoSaveTracks,
                value: _ws.autoSendMusicToMemory,
                onChanged: (v) => _ws.setAutoSendMusicToMemory(v),
              ),
              _settingDivider(),
              _buildSettingToggle(
                icon: Icons.calendar_month_outlined,
                iconColor: _t.iconMood,
                title: _s.moodToCalendar,
                subtitle: _s.autoMarkMoodCalendar,
                value: _ws.autoSendMoodToCalendar,
                onChanged: (v) => _ws.setAutoSendMoodToCalendar(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SLOT ROWS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSlotRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    Color? valueColor,
    Widget? trailing,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasValue = value != null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.rubik(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (hasValue) ...[
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: GoogleFonts.rubik(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: valueColor ?? Colors.grey.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
            if (!hasValue) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _t.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: _t.primary),
                    const SizedBox(width: 2),
                    Text(
                      _s.addBtn,
                      style: GoogleFonts.rubik(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _t.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReadonlySlot({
    required IconData icon,
    required Color iconColor,
    required String label,
    String? value,
    Color? valueColor,
    Widget? trailing,
  }) {
    final hasValue = value != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.rubik(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                if (hasValue) ...[
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.rubik(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          if (!hasValue)
            Text(
              '—',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade300),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.rubik(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.rubik(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: _t.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // HELPERS / BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _t.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _t.cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEditBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _t.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_rounded, size: 12, color: _t.primary),
          const SizedBox(width: 4),
          Text(
            _s.editBtn,
            style: GoogleFonts.rubik(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _t.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotDivider() =>
      Divider(color: Colors.grey.shade100, height: 1, thickness: 1);

  Widget _settingDivider() =>
      Divider(color: Colors.grey.shade100, height: 8, thickness: 1);

  // ════════════════════════════════════════════════════════════════════════════
  // NOT PAIRED PLACEHOLDER
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildNotPaired() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _t.bgImageUrl != null
            ? CachedNetworkImage(
                imageUrl: _t.bgImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _t.bgGradient,
                    ),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _t.bgGradient,
                  ),
                ),
              ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _t.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.widgets_rounded,
                    size: 36,
                    color: _t.primary.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _s.widgetsTitle,
                  style: GoogleFonts.rubik(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _s.connectPartnerForWidgets,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rubik(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DIALOGS / EDITORS
  // ════════════════════════════════════════════════════════════════════════════

  void _showMoodPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoodPickerSheet(
        theme: _t,
        onSelect: (option) async {
          Navigator.pop(ctx);
          _pair.setMood(option.imagePath, option.label);
          // Добавляем в календарь с корректным id
          _moodService.addMood(
            moodId: option.id,
            imagePath: option.imagePath,
            label: option.label,
          );
          // skipCalendar: moodService уже добавил запись — не дублируем
          _ws.updateMood(option.imagePath, option.label, skipCalendar: true);
        },
      ),
    );
  }

  void _showTextEditor({
    required String title,
    required String hint,
    required String initial,
    required int maxLength,
    required ValueChanged<String> onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TextEditorSheet(
        theme: _t,
        title: title,
        hint: hint,
        initial: initial,
        maxLength: maxLength,
        onSave: (value) {
          onSave(value);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhotoSourceSheet(theme: _t),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (file == null || !mounted) return;

    // Показываем лоадер
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                M3LoadingDots(color: _t.primary),
                const SizedBox(height: 16),
                Text(_s.uploadingPhoto, style: GoogleFonts.rubik(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    await _ws.updatePhoto(file.path);
    if (mounted) Navigator.of(context).pop(); // закрываем лоадер
  }

  void _showMusicEditor(WidgetData data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MusicEditorSheet(
        theme: _t,
        initialTitle: data.musicTitle ?? '',
        initialArtist: data.musicArtist ?? '',
        initialUrl: data.musicUrl ?? '',
        onSave: ({required String title, required String artist, String? url}) {
          _ws.updateMusic(title: title, artist: artist, url: url);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _s.resetWidget,
          style: GoogleFonts.rubik(fontWeight: FontWeight.w700),
        ),
        content: Text(_s.resetWidgetConfirm, style: GoogleFonts.rubik()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              _s.cancel,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_s.resetBtn, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _ws.clearAll();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MD3 PHOTO LOADER — анимация загрузки фото
// ══════════════════════════════════════════════════════════════════════════════

class _MD3PhotoLoader extends StatefulWidget {
  final Color color;
  const _MD3PhotoLoader({required this.color});

  @override
  State<_MD3PhotoLoader> createState() => _MD3PhotoLoaderState();
}

class _MD3PhotoLoaderState extends State<_MD3PhotoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ring = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Внешнее пульсирующее кольцо
            Transform.scale(
              scale: 1.0 + _pulse.value * 0.12,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.08 + _pulse.value * 0.07),
                ),
              ),
            ),
            // Среднее кольцо — чуть в противофазе
            Transform.scale(
              scale: 1.0 + (1 - _ring.value) * 0.08,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.06 + (1 - _ring.value) * 0.06),
                ),
              ),
            ),
            // MD3 индикатор загрузки
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: color,
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                backgroundColor: color.withOpacity(0.12),
              ),
            ),
            // Иконка фото в центре
            Opacity(
              opacity: 0.25 + _pulse.value * 0.35,
              child: Icon(Icons.image_rounded, size: 18, color: color),
            ),
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MOOD PICKER SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _MoodPickerSheet extends StatelessWidget {
  final AppTheme theme;
  final ValueChanged<MoodOption> onSelect;

  const _MoodPickerSheet({required this.theme, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            LocaleService.current.chooseMood,
            style: GoogleFonts.rubik(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: MoodOption.all.length,
              itemBuilder: (_, i) {
                final mood = MoodOption.all[i];
                return GestureDetector(
                  onTap: () => onSelect(mood),
                  child: Container(
                    decoration: BoxDecoration(
                      color: mood.color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: mood.color.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(mood.imagePath, width: 36, height: 36),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            mood.label,
                            style: GoogleFonts.rubik(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: mood.color,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TEXT EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _TextEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String title;
  final String hint;
  final String initial;
  final int maxLength;
  final ValueChanged<String> onSave;

  const _TextEditorSheet({
    required this.theme,
    required this.title,
    required this.hint,
    required this.initial,
    required this.maxLength,
    required this.onSave,
  });

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: GoogleFonts.rubik(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: widget.maxLength,
              maxLines: widget.maxLength > 100 ? 3 : 1,
              style: GoogleFonts.rubik(fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: GoogleFonts.rubik(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: widget.theme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => widget.onSave(_ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.theme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  LocaleService.current.save,
                  style: GoogleFonts.rubik(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

// ══════════════════════════════════════════════════════════════════════════════
// PHOTO SOURCE SHEET
// ══════════════════════════════════════════════════════════════════════════════

class _PhotoSourceSheet extends StatelessWidget {
  final AppTheme theme;

  const _PhotoSourceSheet({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            LocaleService.current.chooseSource,
            style: GoogleFonts.rubik(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.camera_alt_rounded,
                  label: LocaleService.current.camera,
                  source: ImageSource.camera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.photo_library_rounded,
                  label: LocaleService.current.gallery,
                  source: ImageSource.gallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: theme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.rubik(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MUSIC EDITOR SHEET
// ══════════════════════════════════════════════════════════════════════════════

/// Supported music services for the info dialog
const List<Map<String, dynamic>> _musicServicesList = [
  {
    'name': 'Spotify',
    'supported': true,
    'color': Color(0xFF1DB954),
    'icon': Icons.music_note_rounded,
  },
  {
    'name': 'YouTube Music',
    'supported': true,
    'color': Color(0xFFFF0000),
    'icon': Icons.play_circle_rounded,
  },
  {
    'name': 'Apple Music',
    'supported': true,
    'color': Color(0xFFFC3C44),
    'icon': Icons.apple_rounded,
  },
  {
    'name': 'Deezer',
    'supported': true,
    'color': Color(0xFFA238FF),
    'icon': Icons.album_rounded,
  },
  {
    'name': 'SoundCloud',
    'supported': true,
    'color': Color(0xFFFF5500),
    'icon': Icons.cloud_rounded,
  },
  {
    'name': 'Яндекс Музыка',
    'supported': true,
    'color': Color(0xFFFFCC00),
    'icon': Icons.library_music_rounded,
  },
  {
    'name': 'Tidal',
    'supported': true,
    'color': Color(0xFF000000),
    'icon': Icons.waves_rounded,
  },
  {
    'name': 'VK Music',
    'supported': true,
    'color': Color(0xFF0077FF),
    'icon': Icons.music_video_rounded,
  },
  {
    'name': 'YouTube',
    'supported': true,
    'color': Color(0xFFFF0000),
    'icon': Icons.smart_display_rounded,
  },
  {
    'name': 'Audio file',
    'supported': true,
    'color': Color(0xFF8B5CF6),
    'icon': Icons.audio_file_rounded,
  },
  {
    'name': 'Amazon Music',
    'supported': false,
    'color': Color(0xFF25D1DA),
    'icon': Icons.shopping_bag_rounded,
  },
  {
    'name': 'Pandora',
    'supported': false,
    'color': Color(0xFF005483),
    'icon': Icons.radio_rounded,
  },
];

class _MusicEditorSheet extends StatefulWidget {
  final AppTheme theme;
  final String initialTitle;
  final String initialArtist;
  final String initialUrl;
  final void Function({
    required String title,
    required String artist,
    String? url,
  })
  onSave;

  const _MusicEditorSheet({
    required this.theme,
    required this.initialTitle,
    required this.initialArtist,
    required this.initialUrl,
    required this.onSave,
  });

  @override
  State<_MusicEditorSheet> createState() => _MusicEditorSheetState();
}

class _MusicEditorSheetState extends State<_MusicEditorSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _artistCtrl = TextEditingController(text: widget.initialArtist);
    _urlCtrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.theme.primary;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // ── Header with info button ──
            Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleService.current.music,
                    style: GoogleFonts.rubik(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showServicesInfo(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── Song Details Section ───
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    primary.withOpacity(0.04),
                    const Color(0xFFEC4899).withOpacity(0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: primary.withOpacity(0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 16,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Song Details',
                        style: GoogleFonts.rubik(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    _titleCtrl,
                    LocaleService.current.trackName,
                    Icons.audiotrack_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    _artistCtrl,
                    LocaleService.current.artist,
                    Icons.person_rounded,
                  ),
                ],
              ),
            ),

            // ─── Divider ───
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Divider(color: Colors.grey.shade200, height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 14, color: primary),
                          const SizedBox(width: 4),
                          Text(
                            'Source',
                            style: GoogleFonts.rubik(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(color: Colors.grey.shade200, height: 1),
                  ),
                ],
              ),
            ),

            // ─── Link Section ───
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Streaming Link',
                        style: GoogleFonts.rubik(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    _urlCtrl,
                    LocaleService.current.linkOptional,
                    Icons.link_rounded,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final title = _titleCtrl.text.trim();
                  final artist = _artistCtrl.text.trim();
                  if (title.isEmpty || artist.isEmpty) return;
                  final url = _urlCtrl.text.trim();
                  widget.onSave(
                    title: title,
                    artist: artist,
                    url: url.isNotEmpty ? url : null,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  LocaleService.current.save,
                  style: GoogleFonts.rubik(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showServicesInfo(BuildContext context) {
    final primary = widget.theme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary.withOpacity(0.15),
                      const Color(0xFFEC4899).withOpacity(0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.music_note_rounded, color: primary, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                'Supported Services',
                style: GoogleFonts.rubik(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Paste a link from any supported service',
                style: GoogleFonts.rubik(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 18),
              ..._musicServicesList.map(
                (svc) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: (svc['color'] as Color).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (svc['color'] as Color).withOpacity(0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          svc['icon'] as IconData,
                          size: 20,
                          color: svc['color'] as Color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            svc['name'] as String,
                            style: GoogleFonts.rubik(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Icon(
                          svc['supported'] == true
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          size: 20,
                          color: svc['supported'] == true
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Got it',
                    style: GoogleFonts.rubik(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.rubik(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.rubik(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: widget.theme.primary, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: widget.theme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
