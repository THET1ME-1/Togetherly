import 'package:flutter/widgets.dart';

/// `StreamBuilder`, который создаёт поток ОДИН раз, а не на каждой перерисовке.
///
/// Обычный `StreamBuilder(stream: repo.watch(id))` пересоздаёт поток при каждом
/// `build`: у `PbRealtimeService` каждая новая подписка зовёт `syncOnce()` и
/// уходит в сеть за списком, а картинки внутри списка пересоздаются вместе с
/// ним и не успевают дописаться в кэш до отмены загрузки. На экране «Хочу с
/// тобой» это дало цикл — 52 запроса `wishes/records` и 180 скачиваний двух
/// аватарок с одного телефона за сорок секунд; по серверу вышло 131 тысяча
/// запросов аватарок из 149 тысяч всех обращений к файлам, то есть 88% раздачи.
///
/// Поток пересоздаётся только когда меняется [keys] — набор значений, от
/// которых он зависит (id пары, uid партнёра). Сравнение поэлементное, поэтому
/// новый список с теми же значениями пересоздания не вызывает.
class StableStreamBuilder<T> extends StatefulWidget {
  const StableStreamBuilder({
    super.key,
    required this.create,
    required this.builder,
    this.keys = const [],
    this.initialData,
  });

  /// Как завести поток. Зовётся один раз на состояние и при смене [keys].
  final Stream<T> Function() create;

  final AsyncWidgetBuilder<T> builder;

  /// От чего поток зависит. Изменились — поток заводится заново.
  final List<Object?> keys;

  final T? initialData;

  @override
  State<StableStreamBuilder<T>> createState() => _StableStreamBuilderState<T>();
}

class _StableStreamBuilderState<T> extends State<StableStreamBuilder<T>> {
  late Stream<T> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.create();
  }

  @override
  void didUpdateWidget(StableStreamBuilder<T> old) {
    super.didUpdateWidget(old);
    if (!_sameKeys(old.keys, widget.keys)) _stream = widget.create();
  }

  static bool _sameKeys(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // stream-ok: поток лежит в поле состояния, создаётся один раз.
    return StreamBuilder<T>(
      stream: _stream,
      initialData: widget.initialData,
      builder: widget.builder,
    );
  }
}
