import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../dict_strings.dart' show trKey;
import '../../models/gift.dart';
import '../../services/pb_media_service.dart';
import '../../theme/profile_theme.dart';
import '../../utils/safe_pick.dart';
import '../app_sheet.dart';
import '../common/gift_image.dart';

/// Лист «приложить снимок» перед отправкой «Кадра».
///
/// Возвращает ссылку `pb://media/…` на загруженный снимок, пустую строку,
/// если человек отправляет без фото, и null, если передумал дарить.
///
/// Снимок загружается сразу после выбора, до рекламы и до списания монет:
/// провал загрузки виден здесь же, и человек не отдаёт ни ролик, ни монеты
/// за подарок, в котором кадр потерялся.
Future<String?> showGiftPhotoSheet(
  BuildContext context, {
  required Gift gift,
  required ColorScheme scheme,
  required String groupId,
  required String uid,
}) {
  return showAppSheet<String>(
    context,
    background: scheme.surfaceContainerHigh,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: SheetScaffold(
        title: gift.title,
        child: _GiftPhotoBody(gift: gift, groupId: groupId, uid: uid),
      ),
    ),
  );
}

class _GiftPhotoBody extends StatefulWidget {
  const _GiftPhotoBody({
    required this.gift,
    required this.groupId,
    required this.uid,
  });

  final Gift gift;
  final String groupId;
  final String uid;

  @override
  State<_GiftPhotoBody> createState() => _GiftPhotoBodyState();
}

class _GiftPhotoBodyState extends State<_GiftPhotoBody> {
  String? _localPath;
  String? _url;
  bool _uploading = false;
  bool _failed = false;

  Future<void> _pick(ImageSource source) async {
    if (_uploading) return;
    final x = await safePick(
      () => ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      ),
    );
    if (x == null || !mounted) return;
    setState(() {
      _localPath = x.path;
      _url = null;
      _failed = false;
      _uploading = true;
    });
    final url = await PbMediaService.instance.uploadFile(
      x.path,
      uid: widget.uid,
      groupId: widget.groupId,
      kind: 'gift',
    );
    if (!mounted || _localPath != x.path) return; // успели выбрать другой
    setState(() {
      _uploading = false;
      _url = (url != null && url.isNotEmpty) ? url : null;
      _failed = _url == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = TextStyle(
      fontFamily: 'Onest',
      fontSize: 14,
      color: cs.onSurfaceVariant,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(trKey('giftPhotoHint'), style: text),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _pick(ImageSource.gallery),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 220,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: cs.surfaceContainerHighest),
                    if (_localPath != null)
                      Image.file(File(_localPath!), fit: BoxFit.cover)
                    else
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GiftImage(widget.gift.key, side: 72),
                          const SizedBox(height: 10),
                          Text(trKey('giftPhotoPick'), style: text),
                        ],
                      ),
                    if (_uploading)
                      ColoredBox(
                        color: cs.scrim.withValues(alpha: 0.35),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_uploading || _failed) ...[
            const SizedBox(height: 8),
            Text(
              trKey(_failed ? 'giftPhotoFailed' : 'giftPhotoUploading'),
              style: text.copyWith(
                fontSize: 13,
                color: _failed ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _uploading
                      ? null
                      : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    trKey('giftPhotoGallery'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _uploading
                      ? null
                      : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    trKey('giftPhotoCamera'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _uploading
                      ? null
                      : () => Navigator.of(context).pop(''),
                  child: Text(trKey('giftPhotoSkip')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _url == null
                      ? null
                      : () => Navigator.of(context).pop(_url),
                  child: Text(trKey('giftPhotoSend')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
