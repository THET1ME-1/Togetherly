import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PhotoDayCarouselEditor extends StatefulWidget {
  final AppTheme theme;
  final List<String> initialPaths;
  final String initialRotationType;
  final int initialRotationInterval;
  final Future<void> Function({
    required List<String> paths,
    required String rotationType,
    required int rotationInterval,
  })
  onSave;

  const PhotoDayCarouselEditor({
    super.key,
    required this.theme,
    required this.initialPaths,
    required this.onSave,
    this.initialRotationType = 'unlock',
    this.initialRotationInterval = 60,
  });

  @override
  State<PhotoDayCarouselEditor> createState() => _PhotoDayCarouselEditorState();
}

class _PhotoDayCarouselEditorState extends State<PhotoDayCarouselEditor> {
  late int _count;
  late List<String?> _paths;
  late String _rotationType;
  late int _rotationInterval;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _paths = widget.initialPaths.map((p) => p as String?).toList();
    _count = _paths.length.clamp(1, 10);
    while (_paths.length < _count) {
      _paths.add(null);
    }
    _rotationType = widget.initialRotationType;
    _rotationInterval = widget.initialRotationInterval;
  }

  void _updateCount(int newCount) {
    if (newCount < 1 || newCount > 10) return;
    setState(() {
      _count = newCount;
      while (_paths.length < _count) {
        _paths.add(null);
      }
      if (_paths.length > _count) {
        _paths = _paths.sublist(0, _count);
      }
    });
  }

  Future<void> _pickPhoto(int index) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (picked != null) {
      setState(() {
        _paths[index] = picked.path;
      });
    }
  }

  Future<void> _save() async {
    final validPaths = _paths.whereType<String>().toList();
    if (validPaths.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        paths: validPaths,
        rotationType: _count >= 2 ? _rotationType : 'none',
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
          Text(
            'Настройка фото',
            style: GoogleFonts.rubik(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.primary,
            ),
          ),
          const SizedBox(height: 16),

          // Photo count selector
          Text(
            'Количество фото (1-10)',
            style: GoogleFonts.rubik(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(10, (i) {
              final num = i + 1;
              final isSelected = _count == num;
              return GestureDetector(
                onTap: () => _updateCount(num),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? t.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? t.primary : Colors.grey.shade300,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$num',
                      style: GoogleFonts.rubik(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Photo slots
          Text(
            'Фото',
            style: GoogleFonts.rubik(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: _count,
            itemBuilder: (context, index) {
              final path = _paths[index];
              return GestureDetector(
                onTap: () => _pickPhoto(index),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: path != null
                          ? t.primary.withOpacity(0.3)
                          : Colors.grey.shade300,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: path != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            path.startsWith('http')
                                ? CachedNetworkImage(
                                    imageUrl: path,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(File(path), fit: BoxFit.cover),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _paths[index] = null;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 24,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${index + 1}',
                              style: GoogleFonts.rubik(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),

          // Rotation settings (only for 2+ photos)
          if (_count >= 2) ...[
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
                      DropdownMenuItem(
                        value: 15,
                        child: Text('Каждые 15 минут'),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text('Каждые 30 минут'),
                      ),
                      DropdownMenuItem(value: 60, child: Text('Каждый час')),
                      DropdownMenuItem(
                        value: 180,
                        child: Text('Каждые 3 часа'),
                      ),
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
              onPressed: _paths.whereType<String>().isEmpty || _isSaving
                  ? null
                  : _save,
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Сохранить',
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
