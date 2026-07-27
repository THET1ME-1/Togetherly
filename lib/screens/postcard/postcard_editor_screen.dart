import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../../utils/safe_pick.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/pair_data.dart';
import '../../models/user_data.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import 'models/postcard_template.dart';
import 'widgets/postcard_card.dart';
import '../../services/pb_data_service.dart';
import '../../services/miss_you_repository.dart';

class PostcardEditorScreen extends StatefulWidget {
  final UserData userData;
  final PairData pairData;
  final AppTheme theme;
  final DateTime? timerStartDate;

  const PostcardEditorScreen({
    super.key,
    required this.userData,
    required this.pairData,
    required this.theme,
    this.timerStartDate,
  });

  @override
  State<PostcardEditorScreen> createState() => _PostcardEditorScreenState();
}

class _PostcardEditorScreenState extends State<PostcardEditorScreen> {
  AppTheme get _t => widget.theme;

  PostcardTemplateId _templateId = PostcardTemplateId.together;
  late List<PostcardTextBlock> _blocks;
  bool _exporting = false;
  /// Правил ли человек текст руками: после этого числа не перетираем.
  bool _blocksEdited = false;
  bool _capturing = false; // true во время снимка — скрывает UI-оверлеи из экспорта

  // Polaroid photo state
  String? _polaroidImagePath;
  Alignment _polaroidAlignment = Alignment.center;

  /// Числа пары для чека. Подтягиваются с сервера при открытии: открытка
  /// показывает то, что приложение уже посчитало, а не выдуманные строки.
  PostcardStats _stats = const PostcardStats();

  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _polaroidKey = GlobalKey();

  int get _days {
    final date = widget.timerStartDate ?? widget.pairData.startDate;
    if (date == null) return 0;
    return DateTime.now().difference(date).inDays;
  }
  String get _myName => widget.userData.displayName;
  String get _partnerName => widget.pairData.partnerDisplayName;

  @override
  void initState() {
    super.initState();
    _resetBlocks();
    _loadStats();
  }

  /// Счётчики группы и «я скучаю». Молча пропускаем ошибку: открытка должна
  /// открыться и без сети, просто без строк с числами.
  Future<void> _loadStats() async {
    final groupId = widget.pairData.pairId;
    if (groupId.isEmpty) return;
    try {
      final group = await PbDataService().loadGroupById(groupId);
      final counts = await MissYouRepository().watchCounts(groupId).first;
      if (!mounted) return;
      final missYou = counts.values.fold<int>(0, (a, b) => a + b);
      setState(() {
        _stats = PostcardStats(
          memories: (group?.data['memories_count'] as num?)?.toInt() ?? 0,
          drawings: (group?.data['drawings_count'] as num?)?.toInt() ?? 0,
          streak: (group?.data['streak_days'] as num?)?.toInt() ?? 0,
          missYou: missYou,
        );
        // Пока человек не правил строки чека руками, подставляем свежие числа.
        if (_templateId == PostcardTemplateId.receipt && !_blocksEdited) {
          _blocks = PostcardTemplate.defaultBlocks(
            templateId: _templateId,
            days: _days,
            myName: _myName,
            partnerName: _partnerName,
            stats: _stats,
          );
        }
      });
    } catch (_) {}
  }

  void _resetBlocks() {
    _blocks = PostcardTemplate.defaultBlocks(
      stats: _stats,
      templateId: _templateId,
      days: _days,
      myName: _myName,
      partnerName: _partnerName,
    );
  }

  void _switchTemplate(PostcardTemplateId id) {
    if (_templateId == id) return;
    setState(() {
      _templateId = id;
      _resetBlocks();
      if (id != PostcardTemplateId.polaroid) {
        _polaroidImagePath = null;
        _polaroidAlignment = Alignment.center;
      }
    });
  }

  Future<void> _pickPolaroidPhoto() async {
    final picker = ImagePicker();
    final picked = await safePick(
      () => picker.pickImage(source: ImageSource.gallery),
    );
    if (picked != null && mounted) {
      setState(() {
        _polaroidImagePath = picked.path;
        _polaroidAlignment = Alignment.center;
      });
    }
  }

  void _editBlock(String blockId) {
    _blocksEdited = true;
    final block = _blocks.firstWhere((b) => b.id == blockId);
    final controller = TextEditingController(text: block.text);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _t.cardSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _t.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                block.label,
                style: AppFonts.onest(size: 13, weight: 600, letterSpacing: 1, color: _t.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: null,
                style: AppFonts.onest(size: 16, color: _t.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _t.primaryLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _t.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final newText = controller.text.trim();
                    if (newText.isNotEmpty) {
                      setState(() {
                        _blocks = _blocks
                            .map((b) => b.id == blockId ? b.copyWith(text: newText) : b)
                            .toList();
                      });
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    LocaleService.current.done,
                    style: AppFonts.onest(size: 15, weight: 700, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    // Геометрию экрана для sharePositionOrigin (iPad-поповер) берём ДО await'ов,
    // пока не пересекли async-gap с BuildContext.
    final shareOrigin = () {
      final box = context.findRenderObject() as RenderBox?;
      return box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    }();
    // Скрываем UI-оверлеи (баджик «потяни» и рамки редактирования)
    setState(() { _exporting = true; _capturing = true; });
    // Ждём РЕАЛЬНО отрисованный кадр без оверлеев. Future.delayed(60ms) не
    // гарантировал готовность кадра → boundary.toImage падал ассертом
    // '!debugNeedsPaint' (debug) или захватывал старый кадр с видимыми рамками
    // (release). endOfFrame форсит кадр и дожидается его завершения.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    ui.Image? image;
    try {
      final captureKey = _templateId == PostcardTemplateId.polaroid
          ? _polaroidKey
          : _cardKey;
      final boundary =
          captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      // Раньше здесь был молчаливый `return`: спиннер гас, шэра нет, ошибки нет
      // — тестер видел «ничего не происходит». Теперь бросаем → SnackBar.
      if (boundary == null) {
        throw StateError('postcard render boundary not ready');
      }

      // pixelRatio 2.5 — качество остаётся высоким, но вдвое меньше пикселей,
      // чем 3.0: полароид с полноразмерным фото больше не ловит OutOfMemory на
      // слабых устройствах (фото декодится с cacheWidth в postcard_card.dart).
      image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('postcard png encode returned null');
      }

      final dir = await getTemporaryDirectory();
      // Имя завязано на контент (дни + шаблон) → системный share-кэш не подхватит
      // устаревший файл от прошлого шэра. flush:true — файл дописан до share.
      final file = File(
          '${dir.path}/togetherly_postcard_${_days}_${_templateId.name}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      // sharePositionOrigin обязателен для share-поповера на iPad (иначе краш).
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '$_days ${LocaleService.current.pcDaysTogether} ❤️',
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleService.current.failedToSave(e))),
        );
      }
    } finally {
      image?.dispose();
      if (mounted) setState(() { _exporting = false; _capturing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _t.bgGradient,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                const SizedBox(height: 16),
                _buildTemplateSelector(),
                if (_templateId == PostcardTemplateId.polaroid) ...[
                  const SizedBox(height: 10),
                  _buildPhotoPickerButton(),
                ],
                const SizedBox(height: 12),
                Expanded(child: _buildCardPreview()),
                _buildEditHint(),
                const SizedBox(height: 16),
                _buildShareButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: _t.primary, size: 20),
          ),
          Expanded(
            child: Text(
              LocaleService.current.postcardTitle,
              style: AppFonts.onest(size: 20, weight: 700, color: _t.textPrimary),
            ),
          ),
          Text(
            LocaleService.current.daysTogetherLabel('$_days'),
            style: AppFonts.onest(size: 13, weight: 600, color: _t.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        separatorBuilder: (context, i) => const SizedBox(width: 10),
        itemCount: PostcardTemplate.all.length,
        itemBuilder: (context, i) {
          final tpl = PostcardTemplate.all[i];
          final isSelected = tpl.id == _templateId;
          return GestureDetector(
            onTap: () => _switchTemplate(tpl.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _t.primary : _t.cardSurface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? _t.primary : _t.divider,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _t.primary.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tpl.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    tpl.title,
                    style: AppFonts.onest(size: 13, weight: 600, color: isSelected ? Colors.white : _t.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: RepaintBoundary(
          key: _cardKey,
          child: PostcardCard(
            templateId: _templateId,
            days: _days,
            blocks: _blocks,
            isEditing: !_capturing,
            onBlockTap: _editBlock,
            polaroidImagePath: _polaroidImagePath,
            polaroidAlignment: _polaroidAlignment,
            onSelectPhoto: _pickPolaroidPhoto,
            onAlignmentChanged: (a) => setState(() => _polaroidAlignment = a),
            polaroidCaptureKey: _polaroidKey,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPickerButton() {
    final hasPhoto = _polaroidImagePath != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _pickPolaroidPhoto,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _t.cardSurface.withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _t.cardBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasPhoto
                    ? Icons.swap_horiz_rounded
                    : Icons.add_photo_alternate_rounded,
                size: 18,
                color: _t.primary,
              ),
              const SizedBox(width: 8),
              Text(
                hasPhoto
                    ? LocaleService.current.changePhoto
                    : LocaleService.current.addPhotoFromGallery,
                style: AppFonts.onest(size: 13, weight: 600, color: _t.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_rounded, size: 14, color: _t.textMuted),
          const SizedBox(width: 6),
          Text(
            LocaleService.current.tapAnyTextToEdit,
            style: AppFonts.onest(size: 12, weight: 400, color: _t.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildShareButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _t.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.share_rounded, color: Colors.white, size: 20),
          label: Text(
            _exporting
                ? LocaleService.current.creating
                : LocaleService.current.sharePostcard,
            style: AppFonts.onest(size: 15, weight: 700, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
