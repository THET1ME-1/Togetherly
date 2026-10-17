import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../models/memory_media.dart';
import '../../services/media_save_queue.dart';
import '../../services/saved_media_ledger.dart';
import '../../theme/fonts.dart';
import '../memory_save/save_flow.dart';

/// Кнопка «Сохранить в галерею» под снимком во весь экран.
///
/// Фото из парного виджета, снимок к «Кадру», фото из чата: всё, что лежит в
/// хранилище пары, уходит в альбом «Togetherly» с датой снимка через ту же
/// очередь, что кадры воспоминаний. Ради одного кадра заводить воспоминание не
/// нужно (обращение 21). Чужие ссылки сохранить нельзя — кнопки нет.
class GallerySaveBar extends StatefulWidget {
  const GallerySaveBar({
    super.key,
    required this.imageUrl,
    required this.title,
    this.takenAt,
  });

  final String imageUrl;

  /// Подпись задания в уведомлении: имя автора снимка.
  final String title;

  /// Когда снят или поставлен снимок; без даты — сейчас.
  final DateTime? takenAt;

  @override
  State<GallerySaveBar> createState() => _GallerySaveBarState();
}

enum _Stage { idle, saving, saved, failed }

class _GallerySaveBarState extends State<GallerySaveBar> {
  _Stage _stage = _Stage.idle;
  SaveJob? _job;

  MediaFile get _file =>
      MediaFile(ref: widget.imageUrl.trim(), kind: SaveKind.photo, index: 0);

  @override
  void initState() {
    super.initState();
    _checkLedger();
  }

  @override
  void dispose() {
    MediaSaveQueue.instance.removeListener(_follow);
    super.dispose();
  }

  Future<void> _checkLedger() async {
    await SavedMediaLedger.instance.load();
    if (!mounted) return;
    if (SavedMediaLedger.instance.containsFile(_file)) {
      setState(() => _stage = _Stage.saved);
    }
  }

  Future<void> _save() async {
    if (_stage == _Stage.saving) return;
    final item = SaveItem(
      memoryId: 'photo:${_file.key}',
      takenAt: widget.takenAt ?? DateTime.now(),
      file: _file,
    );
    final job = await saveToGallery(context, title: widget.title, items: [item]);
    if (!mounted) return;
    if (job == null) {
      // Отказ в доступе или уже в галерее: журнал скажет, что из этого
      await _checkLedger();
      return;
    }
    _job = job;
    setState(() => _stage = _Stage.saving);
    MediaSaveQueue.instance.addListener(_follow);
  }

  // Итог задания доходит через очередь: качает и пишет натив
  void _follow() {
    final job = _job;
    if (job == null || !mounted) return;
    if (job.isDoneAt(0)) {
      MediaSaveQueue.instance.removeListener(_follow);
      setState(() => _stage = _Stage.saved);
    } else if (job.isFailedAt(0) || job.cancelled) {
      MediaSaveQueue.instance.removeListener(_follow);
      setState(() => _stage = _Stage.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isOwnMediaUrl(widget.imageUrl)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final saved = _stage == _Stage.saved;
    final label = switch (_stage) {
      _Stage.idle => trKey('photoSaveButton'),
      _Stage.saving => trKey('photoSaving'),
      _Stage.saved => trKey('photoSaved'),
      _Stage.failed => trKey('photoSaveFailed'),
    };
    final icon = switch (_stage) {
      _Stage.saved => Icons.download_done_rounded,
      _Stage.failed => Icons.refresh_rounded,
      _ => Icons.download_rounded,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: saved || _stage == _Stage.saving ? null : _save,
          icon: _stage == _Stage.saving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: scheme.onPrimary),
                )
              : Icon(icon, size: 22),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: const StadiumBorder(),
            // Сохранённое не зовёт нажать ещё раз: тёмная пилюля вместо цветной
            disabledBackgroundColor: saved ? const Color(0xFF2B2B2B) : null,
            disabledForegroundColor: saved ? Colors.white : null,
            textStyle: AppFonts.onest(size: 17, weight: 700),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          trKey('photoSaveHint'),
          textAlign: TextAlign.center,
          style: AppFonts.onest(size: 12.5, weight: 500, color: Colors.white60),
        ),
      ],
    );
  }
}
