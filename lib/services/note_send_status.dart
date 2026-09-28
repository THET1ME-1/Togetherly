import 'package:flutter/foundation.dart';

/// Где сейчас отправка своего кружка.
enum NoteSendPhase {
  /// Кодек жмёт видео; есть доля готовности.
  compressing,

  /// Файл уходит на сервер.
  uploading,
}

class NoteSendState {
  const NoteSendState(this.phase, [this.progress = 0]);
  final NoteSendPhase phase;

  /// Доля сжатия 0..1; у загрузки её не знаем.
  final double progress;
}

/// Как идёт отправка кружков, по id сообщения.
///
/// До 28.09.2026 своя фигурка стояла с галочками с первой секунды, хотя видео
/// ещё сжималось и грузилось до двух минут: партнёр в это время не видел
/// ничего, а автор думал, что отправил. Состояние пишет очередь
/// (`_applyChatNote`), читает пузырь. Нет записи — значит сейчас с этим
/// сообщением никто не работает: либо ушло, либо ждёт сети в очереди.
class NoteSendStatus extends ChangeNotifier {
  NoteSendStatus._();
  static final NoteSendStatus instance = NoteSendStatus._();

  final Map<String, NoteSendState> _states = {};

  NoteSendState? of(String messageId) => _states[messageId];

  void set(String messageId, NoteSendState state) {
    final old = _states[messageId];
    // Проценты кодека приходят десятками в секунду — перерисовываем только
    // при сдвиге хотя бы на процент.
    if (old != null &&
        old.phase == state.phase &&
        (old.progress - state.progress).abs() < 0.01) {
      return;
    }
    _states[messageId] = state;
    notifyListeners();
  }

  void clear(String messageId) {
    if (_states.remove(messageId) != null) notifyListeners();
  }
}

/// Что показать под своим кружком, пока он не доехал.
enum NoteSendView { none, compressing, uploading, waiting, failed }

/// Правило подписи: провал главнее всего, дальше живая работа очереди, а
/// «ждёт» — когда операция лежит в очереди, но её сейчас никто не трогает.
NoteSendView noteSendView({
  required bool mine,
  required bool pending,
  required bool poisoned,
  required NoteSendState? active,
}) {
  if (!mine) return NoteSendView.none;
  if (poisoned) return NoteSendView.failed;
  if (active != null) {
    return active.phase == NoteSendPhase.compressing
        ? NoteSendView.compressing
        : NoteSendView.uploading;
  }
  return pending ? NoteSendView.waiting : NoteSendView.none;
}
