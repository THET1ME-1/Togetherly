import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../services/locale_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PhotoDayCarouselEditor extends StatefulWidget {
  final AppTheme theme;
  final List<String> initialPaths; // can be local file or http
  final int maxPhotos;
  final String initialRotationType; // 'unlock' | 'time'
  final int initialRotationInterval; // in minutes
  final Future<void> Function({
    required List<String> paths,
    required String rotationType,
    required int rotationInterval,
  }) onSave;

  const PhotoDayCarouselEditor({
    super.key,
    required this.theme,
    required this.initialPaths,
    required this.onSave,
    this.maxPhotos = 10,
    this.initialRotationType = 'unlock',
    this.initialRotationInterval = 60,
  });

  @override
  State<PhotoDayCarouselEditor> createState() => _PhotoDayCarouselEditorState();
}

class _PhotoDayCarouselEditorState extends State<PhotoDayCarouselEditor> {
  late List<String> _paths;
  late String _rotationType;
  late int _rotationInterval;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _paths = List.from(widget.initialPaths);
    _rotationType = widget.initialRotationType;
    _rotationInterval = widget.initialRotationInterval;
  }

  Future<void> _pickPhotos() async {
    if (_paths.length >= widget.maxPhotos) return;

    final picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (var f in pickedFiles) {
          if (_paths.length < widget.maxPhotos) {
            _paths.add(f.path);
          }
        }
      });
    }
  }

  Future<void> _save() async {
    if (_paths.isEmpty) return; // need at least one
    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        paths: _paths,
        rotationType: _rotationType,
        rotationInterval: _rotationInterval,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Error saving carousel: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = LocaleService.current;
    final t = widget.theme;

    return Container(
      decoration: BoxDecoration(
        color: t.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Карусель фото', // s.carouselTitle
                style: GoogleFonts.rubik(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.primary,
                ),
              ),
              if (_paths.length < widget.maxPhotos)
                TextButton.icon(
                  onPressed: _pickPhotos,
                  icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                  label: Text('Добавить'),
                  style: TextButton.styleFrom(foregroundColor: t.primary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Выберите от 1 до ${widget.maxPhotos} фотографий. Перетаскивайте, чтобы изменить порядок.',
            style: GoogleFonts.rubik(
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          
          // Reorderable list of images
          SizedBox(
            height: 120,
            child: _paths.isEmpty
                ? Center(
                    child: Text(
                      'Нет фотографий',
                      style: GoogleFonts.rubik(color: Colors.grey.shade400),
                    ),
                  )
                : ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _paths.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _paths.removeAt(oldIndex);
                        _paths.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (ctx, index) {
                      final path = _paths[index];
                      return Container(
                        key: ValueKey(path),
                        width: 100,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            path.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: path,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(path),
                                    fit: BoxFit.cover,
                                  ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _paths.removeAt(index));
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          
          if (_paths.length > 1) ...[
            const SizedBox(height: 24),
            Text(
              'Менять фото:',
              style: GoogleFonts.rubik(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildRadio(
                    title: 'При разблокировке',
                    value: 'unlock',
                    groupValue: _rotationType,
                    onChanged: (v) => setState(() => _rotationType = v!),
                  ),
                ),
                Expanded(
                  child: _buildRadio(
                    title: 'По времени',
                    value: 'time',
                    groupValue: _rotationType,
                    onChanged: (v) => setState(() => _rotationType = v!),
                  ),
                ),
              ],
            ),
            if (_rotationType == 'time') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _rotationInterval,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('Каждые 15 минут')),
                      DropdownMenuItem(value: 30, child: Text('Каждые 30 минут')),
                      DropdownMenuItem(value: 60, child: Text('Каждый час')),
                      DropdownMenuItem(value: 180, child: Text('Каждые 3 часа')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _rotationInterval = v);
                    },
                  ),
                ),
              ),
            ],
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _paths.isEmpty || _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      s.save,
                      style: GoogleFonts.rubik(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadio({
    required String title,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final isSelected = value == groupValue;
    final t = widget.theme;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? t.primary.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? t.primary : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? t.primary : Colors.grey.shade400,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.rubik(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? t.primary : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}