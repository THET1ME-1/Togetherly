import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common/hint_bubble.dart';
import 'ui_prefs.dart';

/// Очередь одноразовых подсказок о новых функциях.
///
/// Подсказок стало несколько, и показывать их разом нельзя: три пузыря на
/// одном экране — это не объяснение, а завал. Здесь они идут по одной, следующая
/// начинается после того, как закрыли предыдущую. Порядок — тот, в котором их
/// поставили в очередь.
///
/// Каждая подсказка гаснет навсегда: ключ пишется в [UiPrefs] сразу при показе,
/// а не по кнопке «Понятно», — иначе закрытый тапом мимо пузырь возвращался бы
/// при каждом заходе на главную.
class HintQueue {
  HintQueue._();

  static final HintQueue instance = HintQueue._();

  final List<_Pending> _queue = [];
  bool _running = false;

  /// Пауза между подсказками: без неё вторая появляется в тот же кадр, и
  /// человек видит подмену пузыря, а не новую подсказку.
  static const Duration _gap = Duration(milliseconds: 700);

  /// Ставит подсказку в очередь, если её ещё не показывали.
  ///
  /// [key] — ключ в prefs, [targetKey] — виджет, на который смотрит стрелка.
  /// [ready] спрашивают перед самым показом: за время очереди человек мог уйти
  /// с экрана или закрыть пару.
  void enqueue({
    required BuildContext context,
    required String key,
    required GlobalKey targetKey,
    required String text,
    required String gotIt,
    required IconData icon,
    required AppTheme theme,
    HintSide side = HintSide.above,
    bool Function()? ready,
  }) {
    if (_queue.any((h) => h.key == key)) return;
    _queue.add(
      _Pending(
        context: context,
        key: key,
        targetKey: targetKey,
        text: text,
        gotIt: gotIt,
        icon: icon,
        theme: theme,
        side: side,
        ready: ready,
      ),
    );
    unawaited(_pump());
  }

  /// Гасит подсказку навсегда — например, когда человек сам нашёл жест.
  Future<void> markSeen(String key) async {
    _queue.removeWhere((h) => h.key == key);
    await UiPrefs.markHintSeen(key);
  }

  /// Забыть очередь целиком. Нужно тестам: очередь — синглтон, и остаток от
  /// прошлой проверки утекал бы в следующую.
  @visibleForTesting
  void reset() {
    _queue.clear();
    _running = false;
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final hint = _queue.removeAt(0);
        if (await UiPrefs.hintSeen(hint.key)) continue;
        if (!hint.context.mounted) continue;
        if (hint.ready != null && !hint.ready!()) continue;
        if (hint.targetKey.currentContext == null) continue;

        // Ключ пишем перед показом: подсказка одноразовая независимо от того,
        // дочитали её или закрыли тапом мимо.
        await UiPrefs.markHintSeen(hint.key);
        if (!hint.context.mounted) continue;
        await showHintBubble(
          hint.context,
          targetKey: hint.targetKey,
          text: hint.text,
          gotIt: hint.gotIt,
          icon: hint.icon,
          theme: hint.theme,
          side: hint.side,
        );
        if (_queue.isNotEmpty) await Future<void>.delayed(_gap);
      }
    } finally {
      _running = false;
    }
  }
}

class _Pending {
  _Pending({
    required this.context,
    required this.key,
    required this.targetKey,
    required this.text,
    required this.gotIt,
    required this.icon,
    required this.theme,
    required this.side,
    this.ready,
  });

  final BuildContext context;
  final String key;
  final GlobalKey targetKey;
  final String text;
  final String gotIt;
  final IconData icon;
  final AppTheme theme;
  final HintSide side;
  final bool Function()? ready;
}
