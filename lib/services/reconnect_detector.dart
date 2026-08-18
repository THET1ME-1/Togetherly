/// Отличает переподключение сокета от первого соединения.
///
/// После обрыва подписка оживает молча: события, случившиеся в разрыв, не
/// приходят никогда. Для чата это заметно мало (там своя догрузка), а на общем
/// холсте расходятся рисунки — партнёр видит одно, автор другое, и выглядит это
/// как «нарисовал, а у него не сохранилось».
///
/// Догонять пропущенное надо на переподключении и только на нём: на первом
/// соединении список и так только что загрузили, а лишний общий запрос от всех
/// сразу — это тот самый наплыв, которого сервер и без того натерпелся.
class ReconnectDetector {
  bool _everConnected = false;
  bool _droppedSinceConnect = false;

  /// Вернёт true, если это подключение — восстановление после обрыва.
  bool onConnected() {
    if (!_everConnected) {
      _everConnected = true;
      _droppedSinceConnect = false;
      return false;
    }
    if (!_droppedSinceConnect) return false;
    _droppedSinceConnect = false;
    return true;
  }

  void onDisconnected() {
    if (_everConnected) _droppedSinceConnect = true;
  }
}
