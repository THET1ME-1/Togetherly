import 'dart:async';

/// Одна попытка гонки: её будущий результат и способ её прервать.
class RaceAttempt<T> {
  RaceAttempt(this.result, this.cancel);

  final Future<T> result;
  final void Function() cancel;
}

/// Победитель гонки и номер попытки, которая его дала.
class RaceWin<T> {
  const RaceWin(this.value, this.index);

  final T value;
  final int index;
}

/// Попытки по очереди с нахлёстом, как Happy Eyeballs в браузерах: следующая
/// стартует, когда предыдущая провалилась или молчит дольше [stagger], и все
/// начатые идут дальше параллельно. Побеждает первая удачная, остальные
/// прерываются, а запоздавший успех проигравшей отдаётся в [discard] (сокет
/// надо закрыть, иначе он повиснет). Провалились все — летит ошибка ПЕРВОЙ
/// попытки: она про основной путь, и человек должен видеть её, а не запасного.
/// [abort] прерывает всё сразу.
Future<RaceWin<T>> staggeredRace<T>(
  List<RaceAttempt<T> Function()> starters, {
  required Duration stagger,
  void Function(T late)? discard,
  Future<void>? abort,
}) {
  assert(starters.isNotEmpty);
  final done = Completer<RaceWin<T>>();
  final attempts = <RaceAttempt<T>>[];
  Object? firstError;
  StackTrace? firstStack;
  var failed = 0;
  Timer? timer;

  void cancelAll({int except = -1}) {
    for (var i = 0; i < attempts.length; i++) {
      if (i != except) attempts[i].cancel();
    }
  }

  void startNext() {
    timer?.cancel();
    if (done.isCompleted || attempts.length >= starters.length) return;
    final index = attempts.length;
    final attempt = starters[index]();
    attempts.add(attempt);
    attempt.result.then(
      (value) {
        if (done.isCompleted) {
          discard?.call(value);
          return;
        }
        timer?.cancel();
        cancelAll(except: index);
        done.complete(RaceWin(value, index));
      },
      onError: (Object error, StackTrace stack) {
        if (index == 0) {
          firstError = error;
          firstStack = stack;
        }
        failed++;
        if (done.isCompleted) return;
        if (failed == starters.length) {
          done.completeError(firstError ?? error, firstStack ?? stack);
        } else if (index == attempts.length - 1) {
          // Упала последняя начатая: ждать нахлёста незачем.
          startNext();
        }
      },
    );
    if (attempts.length < starters.length) {
      timer = Timer(stagger, startNext);
    }
  }

  abort?.then((_) {
    if (done.isCompleted) return;
    timer?.cancel();
    cancelAll();
    done.completeError(StateError('гонка прервана'));
  });
  startNext();
  return done.future;
}
