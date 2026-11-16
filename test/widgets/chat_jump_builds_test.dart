import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/chat_window.dart';

// Почему лента чата берёт только окно новейших сообщений (жалоба 16.11.2026,
// «приложение не отвечает» в чате на Android).
//
// Неперевёрнутый ListView.builder не знает высоты рядов. Прыжок вниз
// (`jumpTo(maxScrollExtent)` при открытии) раскладывает КАЖДЫЙ ряд по пути до
// низа, а потом выбрасывает их разом. У каждого пузыря свой тикер, и разбор
// тысячи пузырей в одном кадре упирался в `ChangeNotifier.removeListener`:
// в отчётах Google Play это первое место среди зависаний 1.43.

/// Ряд как пузырь чата: свой тикер, как у `_SwipeToReply`.
class _Row extends StatefulWidget {
  const _Row({required this.onBuild});
  final VoidCallback onBuild;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const SizedBox(height: 56);
  }
}

Future<int> _rowsBuiltOnJump(WidgetTester tester, int count) async {
  var built = 0;
  final controller = ScrollController();
  await tester.pumpWidget(MaterialApp(
    home: ListView.builder(
      controller: controller,
      cacheExtent: 600,
      itemCount: count,
      itemBuilder: (_, i) => _Row(onBuild: () => built++),
    ),
  ));
  built = 0;
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pump();
  return built;
}

void main() {
  testWidgets('прыжок вниз по всей истории строит каждый ряд', (tester) async {
    final built = await _rowsBuiltOnJump(tester, 3000);
    expect(built, greaterThan(2500));
  });

  testWidgets('прыжок вниз по окну ленты строит не больше окна', (tester) async {
    final all = List<int>.generate(3000, (i) => i);
    final window = chatWindow<int>(all, limit: 30, floorTs: null, tsOf: (x) => x);
    final built = await _rowsBuiltOnJump(tester, window.length);
    expect(built, lessThanOrEqualTo(30));
  });
}
