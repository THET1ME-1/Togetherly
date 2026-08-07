import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/theme_scope.dart';

/// Тема экрана, пережившая его уход.
///
/// Нижний лист живёт в дереве навигатора и переживает размонтирование экрана,
/// который его открыл. Колбэк такого листа дёргает `context` мёртвого состояния,
/// а `State.context` — это `_element!`: после `dispose` там null, и приложение
/// падает с «Null check operator used on a null value». На 1.24.0+166 так
/// уходило 88 событий за день только из профиля.
class _Probe extends StatefulWidget {
  const _Probe({required this.onReady});

  final void Function(_ProbeState state) onReady;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with RememberedTheme<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onReady(this);
  }

  @override
  Widget build(BuildContext context) {
    // Обращение к теме при живом экране запоминает её.
    return SizedBox(width: 1, height: 1, child: Text('${rememberedTheme.brightness}'));
  }
}

void main() {
  testWidgets('тема помнится и после ухода экрана', (tester) async {
    late _ProbeState state;
    await tester.pumpWidget(
      ThemeScope(
        theme: AppThemes.mint,
        child: MaterialApp(
          home: _Probe(onReady: (s) => state = s),
        ),
      ),
    );

    final whileAlive = state.rememberedTheme;
    expect(whileAlive.name, AppThemes.mint.name);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(state.mounted, isFalse);

    // Главное: геттер не бросает и отдаёт ту же тему.
    expect(state.rememberedTheme.name, AppThemes.mint.name);
  });

  testWidgets('без единого обращения при жизни отдаётся тема по умолчанию',
      (tester) async {
    late _ProbeState state;
    await tester.pumpWidget(
      MaterialApp(home: _Probe(onReady: (s) => state = s)),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(() => state.rememberedTheme, returnsNormally);
  });
}
