import 'dart:async';

import 'package:flutter/material.dart';

import '../../dict_strings.dart';
import '../../services/gallery_writer.dart';
import '../../services/media_save_queue.dart';

/// Островок над лентой воспоминаний: сохранение в галерею живёт здесь, а не
/// держит человека на экране воспоминания.
///
/// Пока идёт — кольцо, «Сохраняю в галерею» и «Лето на Днестре · 37/94», крестик
/// останавливает. По окончании — «В галерее: 94 · Открыть» на несколько
/// секунд. Если что-то не сохранилось, островок ждёт решения: «Повторить» или
/// крестик.
class SaveIsland extends StatefulWidget {
  const SaveIsland({
    super.key,
    this.queue,
    this.autoHide = const Duration(seconds: 6),
  });

  final MediaSaveQueue? queue;
  final Duration autoHide;

  static const Key closeKey = ValueKey('save-island-close');
  static const Key openKey = ValueKey('save-island-open');
  static const Key retryKey = ValueKey('save-island-retry');

  @override
  State<SaveIsland> createState() => _SaveIslandState();
}

class _SaveIslandState extends State<SaveIsland> {
  MediaSaveQueue get _q => widget.queue ?? MediaSaveQueue.instance;
  Timer? _hide;
  SaveJob? _timedFor;

  @override
  void initState() {
    super.initState();
    _q.addListener(_changed);
  }

  @override
  void dispose() {
    _q.removeListener(_changed);
    _hide?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Таймер заводится при отрисовке, а не в слушателе: слушателя зовёт код
  /// очереди, и его часы — это часы загрузки, а не экрана.
  void _scheduleHide(SaveJob fin) {
    if (identical(fin, _timedFor)) return;
    _hide?.cancel();
    _timedFor = fin;
    if (fin.cancelled) {
      // Остановленное человеком итога не требует.
      scheduleMicrotask(_q.dismissFinished);
    } else if (fin.failed == 0 && !fin.accessDenied) {
      _hide = Timer(widget.autoHide, () {
        if (identical(_q.lastFinished, fin)) _q.dismissFinished();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _q.current;
    final fin = job == null ? _q.lastFinished : null;
    if (fin != null) _scheduleHide(fin);
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (job != null) {
      child = _running(context, job);
    } else if (fin != null && !fin.cancelled) {
      child = _finished(context, fin);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
              .animate(a),
          child: c,
        ),
      ),
      child: child,
    );
  }

  Widget _shell(BuildContext context, {
    required Key key,
    required Widget lead,
    required String title,
    required String sub,
    Widget? action,
    required VoidCallback onClose,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: key,
      color: cs.inverseSurface,
      borderRadius: BorderRadius.circular(33),
      child: SizedBox(
        height: 66,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 10),
          child: Row(
            children: [
              SizedBox(width: 42, height: 42, child: Center(child: lead)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onInverseSurface,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 12,
                        color: cs.onInverseSurface.withValues(alpha: 0.78),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 6), action],
              IconButton(
                key: SaveIsland.closeKey,
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: cs.onInverseSurface),
                style: IconButton.styleFrom(
                  backgroundColor: cs.onInverseSurface.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _running(BuildContext context, SaveJob job) {
    final cs = Theme.of(context).colorScheme;
    return _shell(
      context,
      key: const ValueKey('running'),
      lead: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          value: job.progress.clamp(0.02, 1.0),
          strokeWidth: 3.6,
          color: cs.inversePrimary,
          backgroundColor: cs.onInverseSurface.withValues(alpha: 0.2),
        ),
      ),
      title: trKey('islandSaving'),
      sub: '${job.title} · ${job.done}/${job.total}',
      onClose: () => _q.cancel(job.id),
    );
  }

  Widget _finished(BuildContext context, SaveJob job) {
    final cs = Theme.of(context).colorScheme;
    final label = TextStyle(
      fontFamily: 'Onest',
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: cs.inversePrimary,
    );
    if (job.accessDenied) {
      return _shell(
        context,
        key: const ValueKey('denied'),
        lead: Icon(Icons.no_photography_rounded, color: cs.onInverseSurface),
        title: trKey('islandNoAccess'),
        sub: job.title,
        onClose: _q.dismissFinished,
      );
    }
    if (job.failed > 0) {
      return _shell(
        context,
        key: const ValueKey('failed'),
        lead: Icon(Icons.error_outline_rounded, color: cs.onInverseSurface),
        title: trKey('islandFailed').replaceAll('{n}', '${job.failed}'),
        sub: '${job.title} · ${trKey('islandDone').replaceAll('{n}', '${job.done}')}',
        action: TextButton(
          key: SaveIsland.retryKey,
          onPressed: () => _q.retryFailed(job.id),
          child: Text(trKey('islandRetry'), style: label),
        ),
        onClose: _q.dismissFinished,
      );
    }
    return _shell(
      context,
      key: const ValueKey('done'),
      lead: Icon(Icons.download_done_rounded, color: cs.inversePrimary, size: 26),
      title: trKey('islandDone').replaceAll('{n}', '${job.done}'),
      sub: job.title,
      action: TextButton(
        key: SaveIsland.openKey,
        onPressed: () {
          GalleryWriter.instance.open(job.lastUri);
          _q.dismissFinished();
        },
        child: Text(trKey('islandOpen'), style: label),
      ),
      onClose: _q.dismissFinished,
    );
  }
}
